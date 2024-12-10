#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <float.h>
#include <vector>
#include <algorithm>
#include <cuda_runtime.h>
#include <cuda_fp16.h>
#include <cuda_bf16.h>
#include <cuda_fp8.h>
#include <mma.h>
using namespace nvcuda;

#define WARP_SIZE 32
#define DEVICE_INLINE __device__ inline
#define HOST_DEVICE_INLINE __device__ __host__ inline
#define INT4(value) (reinterpret_cast<int4*>(&(value))[0])
#define FLOAT4(value) (reinterpret_cast<float4*>(&(value))[0])
#define HALF2(value) (reinterpret_cast<half2*>(&(value))[0])
#define BFLOAT2(value) (reinterpret_cast<__nv_bfloat162*>(&(value))[0])
#define LDST32BITS(value) (reinterpret_cast<half2*>(&(value))[0])
#define LDST64BITS(value) (reinterpret_cast<float2*>(&(value))[0])
#define LDST128BITS(value) (reinterpret_cast<float4*>(&(value))[0])
// gmem -> smem
#define CP_ASYNC_COMMIT_GROUP() asm volatile("cp.async.commit_group;\n" ::)
#define CP_ASYNC_WAIT_ALL() asm volatile("cp.async.wait_all;\n" ::)
#define CP_ASYNC_WAIT_GROUP(n) asm volatile("cp.async.wait_group %0;\n" ::"n"(n))
// ca(cache all, L1 + L2): support 4, 8, 16 bytes, cg(cache global, L2): only support 16 bytes.
#define CP_ASYNC_CA(dst, src, bytes) asm volatile("cp.async.ca.shared.global.L2::128B [%0], [%1], %2;\n" ::"r"(dst), "l"(src), "n"(bytes))
#define CP_ASYNC_CG(dst, src, bytes) asm volatile("cp.async.cg.shared.global.L2::128B [%0], [%1], %2;\n" ::"r"(dst), "l"(src), "n"(bytes))
// smem -> gmem: requires sm_90 or higher.
#define CP_ASYNC_BULK_COMMIT_GROUP() asm volatile("cp.async.bulk.commit_group;\n" ::)
#define CP_ASYNC_BULK_WAIT_ALL() asm volatile("cp.async.bulk.wait_all;\n" ::)
#define CP_ASYNC_BULK_WAIT_GROUP(n) asm volatile("cp.async.bulk.wait_group %0;\n" ::"n"(n))
#define CP_ASYNC_BULK(dst, src, bytes) asm volatile("cp.async.bulk.global.shared::cta.bulk_group.L2::128B [%0], [%1], %2;\n" ::"r"(dst), "l"(src), "n"(bytes))
// ldmatrix
#define LDMATRIX_X1(R, addr) asm volatile("ldmatrix.sync.aligned.x1.m8n8.shared.b16 {%0}, [%1];\n" : "=r"(R) : "r"(addr))
#define LDMATRIX_X2(R0, R1, addr) asm volatile("ldmatrix.sync.aligned.x2.m8n8.shared.b16 {%0, %1}, [%2];\n" : "=r"(R0), "=r"(R1) : "r"(addr))
#define LDMATRIX_X4(R0, R1, R2, R3, addr) asm volatile("ldmatrix.sync.aligned.x4.m8n8.shared.b16 {%0, %1, %2, %3}, [%4];\n" : "=r"(R0), "=r"(R1), "=r"(R2), "=r"(R3) : "r"(addr))
#define LDMATRIX_X1_T(R, addr) asm volatile("ldmatrix.sync.aligned.x1.trans.m8n8.shared.b16 {%0}, [%1];\n" : "=r"(R) : "r"(addr))
#define LDMATRIX_X2_T(R0, R1, addr) asm volatile("ldmatrix.sync.aligned.x2.trans.m8n8.shared.b16 {%0, %1}, [%2];\n" : "=r"(R0), "=r"(R1) : "r"(addr))
#define LDMATRIX_X4_T(R0, R1, R2, R3, addr) asm volatile("ldmatrix.sync.aligned.x4.trans.m8n8.shared.b16 {%0, %1, %2, %3}, [%4];\n" : "=r"(R0), "=r"(R1), "=r"(R2), "=r"(R3) : "r"(addr))
// stmatrix: requires sm_90 or higher.
#define STMATRIX_X1(addr, R) asm volatile("stmatrix.sync.aligned.x1.m8n8.shared.b16 [%0], {%1};\n" :: "r"(addr), "r"(R))
#define STMATRIX_X2(addr, R0, R1) asm volatile("stmatrix.sync.aligned.x2.m8n8.shared.b16 [%0], {%1, %2};\n" :: "r"(addr), "r"(R0), "r"(R1))
#define STMATRIX_X4(addr, R0, R1, R2, R3) asm volatile("stmatrix.sync.aligned.x4.m8n8.shared.b16 [%0], {%1, %2, %3, %4};\n" :: "r"(addr), "r"(R0), "r"(R1), "r"(R2), "r"(R3))
#define STMATRIX_X1_T(addr, R) asm volatile("stmatrix.sync.aligned.x1.trans.m8n8.shared.b16 [%0], {%1};\n" :: "r"(addr), "r"(R))
#define STMATRIX_X2_T(addr, R0, R1) asm volatile("stmatrix.sync.aligned.x2.trans.m8n8.shared.b16 [%0], {%1, %2};\n" :: "r"(addr), "r"(R0), "r"(R1))
#define STMATRIX_X4_T(addr, R0, R1, R2, R3) asm volatile("stmatrix.sync.aligned.x4.trans.m8n8.shared.b16 [%0], {%1, %2, %3, %4};\n" :: "r"(addr), "r"(R0), "r"(R1), "r"(R2), "r"(R3))
// mma m16n8k16
#define HMMA16816(RD0, RD1, RA0, RA1, RA2, RA3, RB0, RB1, RC0, RC1) asm volatile("mma.sync.aligned.m16n8k16.row.col.f16.f16.f16.f16 {%0, %1}, {%2, %3, %4, %5}, {%6, %7}, {%8, %9};\n" : "=r"(RD0), "=r"(RD1) : "r"(RA0), "r"(RA1), "r"(RA2), "r"(RA3), "r"(RB0), "r"(RB1), "r"(RC0), "r"(RC1))
#define HMMA16816F32(RD0, RD1, RD2, RD3, RA0, RA1, RA2, RA3, RB0, RB1, RC0, RC1, RC2, RC3) asm volatile("mma.sync.aligned.m16n8k16.row.col.f32.f16.f16.f32 {%0,  %1,  %2,  %3}, {%4, %5, %6, %7}, {%8, %9}, {%10, %11, %12, %13};\n" : "=r"(RD0), "=r"(RD1), "=r"(RD2), "=r"(RD3): "r"(RA0), "r"(RA1), "r"(RA2), "r"(RA3), "r"(RB0), "r"(RB1), "r"(RC0), "r"(RC1), "r"(RC2), "r"(RC3))


HOST_DEVICE_INLINE 
int div_ceil(int a, int b) { return (a % b != 0) ? (a / b + 1) : (a / b); }


template<typename T, const int kWarpSize = WARP_SIZE>
DEVICE_INLINE T warp_reduce_sum(T val) {
  #pragma unroll
  for (int mask = kWarpSize >> 1; mask >= 1; mask >>= 1) {
    val += __shfl_xor_sync(0xffffffff, val, mask);
  }
  return val;
}


template<typename T, const int kWarpSize = WARP_SIZE>
DEVICE_INLINE T warp_reduce_max(T val) {
  #pragma unroll
  for (int mask = kWarpSize >> 1; mask >= 1; mask >>= 1) {
    T val_compare = __shfl_xor_sync(0xffffffff, val, mask);
    val = val > val_compare ? val : val_compare;
  }
  return val;
}


template<typename T, int M, const int N, const int K = 2>
DEVICE_INLINE void fill_3D_regs(T (&R)[M][N][K], T val) {
  #pragma unroll
  for (int i = 0; i < M; ++i) {
    #pragma unroll
    for (int j = 0; j < N; ++j) {
      #pragma unroll
      for (int k = 0; k < K; ++k) {
        R[i][j][k] = val;
      }
    }
  }
}


template<typename T, int M, const int N = 2>
DEVICE_INLINE void fill_2D_regs(T (&R)[M][N], T val) {
  #pragma unroll
  for (int i = 0; i < M; ++i) {
    #pragma unroll
    for (int j = 0; j < N; ++j) {
      R[i][j] = val;
    }
  }
}

#define INFHALF __float2half(65536.0f)
#define ZEROHALF __float2half(0.0f)

#define FLASH_ATTN_MMA_DEBUG
#define FLASH_ATTN_MMA_DEBUG_MORE

#ifdef FLASH_ATTN_MMA_DEBUG
#define FA_MMA_PRINT_T0_REG(R, format, ...)      \
{                                                \
  if (tid == 0) {                                \
    float2 v_reg = __half22float2(HALF2(R));     \
    printf("[T0] ");                             \
    printf(format, ##__VA_ARGS__);               \
    printf(", V0=%f, V1=%f\n", v_reg.x, v_reg.y);\
  }                                              \
}
#define FA_MMA_PRINT_REG(R, format, ...)         \
{                                                \
  {                                              \
    float2 v_reg = __half22float2(HALF2(R));     \
    printf(format", V0=%f, V1=%f\n",             \
           ##__VA_ARGS__, v_reg.x, v_reg.y);     \
  }                                              \
}
#define FA_MMA_PRINT_T0(format, ...)            \
{                                               \
  if (tid == 0) {                               \
    printf("[T0] ");                            \
    printf(format, ##__VA_ARGS__);              \
  }                                             \
}
#define FA_MMA_PRINT_L0_REG(R, format, ...)       \
{                                                 \
  if (lane_id == 0) {                             \
    float2 v_reg = __half22float2(HALF2(R));      \
    printf("[L0] ");                              \
    printf(format, ##__VA_ARGS__);                \
    printf(", V0=%f, V1=%f\n", v_reg.x, v_reg.y); \
  }                                               \
}
#define FA_MMA_PRINT_L0(format, ...)            \
{                                               \
  if (lane_id == 0) {                           \
    printf("[L0] ");                            \
    printf(format, ##__VA_ARGS__);              \
  }                                             \
}
#else
#define FA_MMA_PRINT_REG(R, format, ...) {}
#define FA_MMA_PRINT_T0_REG(R, format, ...) {}
#define FA_MMA_PRINT_L0_REG(R, format, ...) {}
#define FA_MMA_PRINT_T0(format, ...) {}
#define FA_MMA_PRINT_L0(format, ...) {}
#endif
// Write FlashAttention-2 from scratch using Tensor Cores with MMA PTX instruction.
// The input is Q,K,V, 4D tensor with shape [batch_size, num_heads, seq_len, head_dim].
// The output is O, a 4D tensor with shape [batch_size, num_heads, seq_len, head_dim].

// The FlashAttention-2 algorithm is described in the following paper:
// https://arxiv.org/abs/2110.08210

// Q,K,V,O: [batch_size, num_heads, seq_len, head_dim], [B,H,N,d]
// each block processes Q_tile with shape [Br,d] and full K,V with shape [N,d]
// Br or Bc = 64,128,256, etc.

// [64,64], m16n8k16, mma2x4, warp2x2(32,16,16)
// (32x2,16x4,16)=(64,64,16), 256 threads, 8 warps.
// default: Br=128|64, Bc=128|64, d=64|128, kStage=2, kPad=0
// tiling: Q_tile[Br,d]=[128,64], K/V_tile[Bc,d]=[128,64]
// outputs: O_tile[Br,d], lse=logsumexp[Br] per thread block.
// iteration: loop over N for K/V with K/V_tile[Bc,d], Tc iters.
// launch: grid(batch, head_num, N/Br=Tr), block(256=8*mma)
// TODO: may return lse=logsumexp[Br].

template<
         const int kHeadDim,          // Headdim, 32,64,128     
         const int kMmaAtomM,         // MMA Atom M, 16
         const int kMmaAtomN,         // MMA Atom N, 8
         const int kMmaAtomK,         // MMA Atom K, 16
         const int kMmaTileSeqLenQ,   // 2, more MMA(warp), M=16*2=32, Q@K^T=[Br(M), d(K)]@[d(K),  Bc(N)]  
         const int kMmaTileSeqLenK,   // 4, more MMA(warp), N=8*4= 32, Q@K^T=[Br(M), d(K)]@[d(K),  Bc(N)]    
         const int kMmaTileSeqLenP,   // 2, more MMA(warp), M=16*2=32, P@V  =[Br(M),Bc(K)]@[Bc(K), d(N) ]
         const int kMmaTileHeadDimV,  // 4, more MMA(warp), N=8*4= 32, P@V  =[Br(M),Bc(K)]@[Bc(K), d(N) ]       
         const int kWarpTileSeqLenQ,  // 2, more values, M, Br=32*2=64, matmul M 
         const int kWarpTileSeqLenK,  // 2, more values, N, Bc=32*2=64, matmul N
         const int kWarpTileSeqLenP,  // 2, more values, M, Br=32*2=64, matmul M
         const int kWarpTileHeadDimV, // 2, more values, N, d=32*(1|2|3|4|...)=32|64|96|128|...
         const int kStage, 
         const int kPad
         >
__global__ void flash_attn_mma_kernel(half* Q, half* K, half* V, half* O, 
                                      const int QKV_seqlen) {
  // Matmul Layout: Q[Br,d]@K^T[d,Bc] NN, P[Br,Bc]@V[Bc,d] NN, all row major.
  static_assert(kMmaAtomM == 16 && kMmaAtomN == 8 && kMmaAtomK == 16); // m16n8k16
  static_assert(kMmaTileSeqLenQ  == 2 && kMmaTileSeqLenK  == 4); // Q@K^T
  static_assert(kMmaTileSeqLenP  == 2 && kMmaTileHeadDimV == 4); // P@V
  static_assert(kWarpTileSeqLenQ == 2 && kWarpTileSeqLenK == 2); // Q@K^T
  // e.g, kWarpTileHeadDimV: 1->d 32, 2->d 64, 3->d 96, 4-> d 128, ..., etc.
  static_assert(kWarpTileSeqLenP == 2 && kWarpTileHeadDimV == (
    kHeadDim / (kMmaAtomN * kMmaTileHeadDimV))); // P@V
  static_assert(kStage > 0 && kStage < 3); // 1,2
  static_assert(kPad >= 0 && kPad % 8 == 0); // 0,8,16
  constexpr int Br = kMmaAtomM * kMmaTileSeqLenQ * kWarpTileSeqLenQ; // 16*2*2=64
  constexpr int Bc = kMmaAtomN * kMmaTileSeqLenK * kWarpTileSeqLenK; // 8*4*2=64
  constexpr int KNumThreads = WARP_SIZE * kMmaTileSeqLenQ * kMmaTileSeqLenK; // 32*2*4=256, num threads
  // Now, N must be mutliples of Bc(32/64) for KV tiling across seqlen.
  const int Tr = div_ceil(QKV_seqlen, Br); // Tr Q_tile[Br,d]
  const int Tc = div_ceil(QKV_seqlen, Bc); // Tc K^T_tile[d,Bc]
  const float scale = 1.0f / sqrt((float) kHeadDim);
  
  // Launch: grid(batch, head_num, N/Br=Tr), block(256=8*mma or 128=4*mma)
  const int QKV_batch_id = blockIdx.x;      // Batch size, bx
  const int QKV_head_id  = blockIdx.y;      // Head num, by
  const int Q_tile_id    = blockIdx.z;      // Q tile_id, range [0, Tr), bz.
  const int O_tile_id    = Q_tile_id;       // O tile_id, same as Q.
  const int tid          = threadIdx.x;     // within block
  const int warp_id      = tid / WARP_SIZE; // 0~7 warp_id within block
  const int lane_id      = tid % WARP_SIZE; // 0~31
  const int warp_QP      = warp_id % 2;     // 0,1
  const int warp_KV      = warp_id / 2;     // 0,1,2,3
  // The layout of 8 MMA(2x4) [before] kWarpTileSeqLenQxkWarpTileSeqLenK(2x2) -> 16x2,8x4=32x32:
  // |  [32,32]  | warp_KV 0 | warp_KV 1 | warp_KV 2 | warp_KV 3 |
  // | warp_QP 0 |-- MMA 0 --|-- MMA 2 --|-- MMA 4 --|-- MMA 6 --|
  // | warp_QP 1 |-- MMA 1 --|-- MMA 3 --|-- MMA 5 --|-- MMA 7 --|
  // The layout of 8 MMA(2x4)  [after] kWarpTileSeqLenQxkWarpTileSeqLenK(2x2) -> 32x2,32x2=64x64: 
  // |  [64,64]  |    warp_KV 0    |    warp_KV 1    |    warp_KV 2    |    warp_KV 3    |
  // | warp_QP 0 |-- MMA 0,MMA 0 --|-- MMA 2,MMA 2 --|-- MMA 4,MMA 4 --|-- MMA 6,MMA 6 --|
  // | warp_QP 0 |-- MMA 0,MMA 0 --|-- MMA 2,MMA 2 --|-- MMA 4,MMA 4 --|-- MMA 6,MMA 6 --|
  // | warp_QP 1 |-- MMA 1,MMA 1 --|-- MMA 3,MMA 2 --|-- MMA 5,MMA 5 --|-- MMA 7,MMA 7 --|
  // | warp_QP 1 |-- MMA 1,MMA 1 --|-- MMA 3,MMA 2 --|-- MMA 5,MMA 5 --|-- MMA 7,MMA 7 --|
  // gridDim.y = head_num, gridDim.z = N/Br = Tr.
  const int Q_gmem_offset = ((QKV_batch_id * gridDim.y * QKV_seqlen * kHeadDim) + 
                             (QKV_head_id * QKV_seqlen * kHeadDim)); // Q [seqlen,d]
  const int K_gmem_offset = ((QKV_batch_id * gridDim.y * kHeadDim * QKV_seqlen) + 
                             (QKV_head_id * kHeadDim * QKV_seqlen)); // transpose K, [d,seqlen]
  const int V_gmem_offset = Q_gmem_offset; // V [seqlen,d]
  const int O_gmem_offset = Q_gmem_offset; // O [seqlen,d]
  
  // Shared memory for Q,K,V,O, d=64->24M, d=128=48M
  extern __shared__ half smem[];
  constexpr int Q_tile_size = Br * (kHeadDim + kPad); // 64*64=4096, ~8192 bytes=8M
  constexpr int K_tile_size = kHeadDim * (Bc + kPad); // 64*64=4096, ~8192 bytes=8M, KV may shared 8M
  constexpr int V_tile_size = Bc * (kHeadDim + kPad); // 64*64=4096, ~8192 bytes=8M, KV may shared 8M
  // K multi-stages: currently, only apply multi stages for K across seq_len.
  half* Q_tile_smem = smem; // 8M/16M
  half* K_tile_smem = Q_tile_smem + Q_tile_size; // 8M/16M
  half* V_tile_smem = K_tile_smem + kStage * K_tile_size; 
  // TODO: KV may shared same smem to reduce smem usage for headdim>=256
  // half* V_tile_smem = K_tile_smem; // KV may shared same smem 8M/16M
  // stage 2, no shared KV smem, Br=Bc=64,  d=64: 8M+(8M)*2+8M   =32M,  shared KV smem: 24M
  // stage 2, no shared KV smem, Br=Bc=64, d=128: 16M+(16M)*2+16M=64M,  shared KV smem: 48M
  // stage 2, no shared KV smem, Br=Bc=64, d=256: 32M+(32M)*2+32M=128M, shared KV smem: 96M
  // stage 1, no shared KV smem, Br=Bc=64, d=256: 32M+(32M)*1+32M=96M,  shared KV smem: 64M
 
  // Mapping Q gmem -> tid -> smem, Q[Br,d]=[64,64 or 128], 256 threads.
  int load_smem_Q_Br = (tid / (KNumThreads / Br)); // Br 64, tid / 4, row 0~64
  int load_smem_Q_d  = (tid % (KNumThreads / Br)) * (kHeadDim / (KNumThreads / Br)); // (tid % 4) * 16, 0,16,32,48
  // Mapping K gmem -> tid -> smem, K^T[d,Bc]=[64 or 128,64], 256 threads.
  int load_smem_K_d  = (tid / (KNumThreads / kHeadDim)); // d 64, tid / 4, row 0~64
  int load_smem_K_Bc = (tid % (KNumThreads / kHeadDim)) * (Bc / (KNumThreads / kHeadDim)); // (tid % 4) * 16, 0,16,32,48
  // Mapping V gmem -> tid -> smem, V[Bc,d]=[64,64 or 128], 256 threads.
  int load_smem_V_Bc = (tid / (KNumThreads / Bc)); // Bc 64, tid / 4, row 0~64
  int load_smem_V_d  = (tid % (KNumThreads / Bc)) * (kHeadDim / (KNumThreads / Bc)); // (tid % 4) * 16, 0,16,32,48
  // global Q row of current head for tile [Br,d] per block.
  int load_gmem_Q_Br = Q_tile_id * Br + load_smem_Q_Br; 
  if (load_gmem_Q_Br >= QKV_seqlen) return;
  // KV tile gmem load index starts from 0 and increments with 
  // each iteration as we loop over seqlen.
  int load_gmem_K_Bc_offset = 0; 
  int load_gmem_V_Bc_offset = 0; 

  uint32_t smem_Q_base_ptr = __cvta_generic_to_shared(Q_tile_smem);
  uint32_t smem_K_base_ptr = __cvta_generic_to_shared(K_tile_smem);
  uint32_t smem_V_base_ptr = __cvta_generic_to_shared(V_tile_smem);

  // --------------------- Registers/SMEM for thread block -------------------------
  // block m_old, l_old, store in lane, use float to keep precision.
  float lane_block_row_max_old[kWarpTileSeqLenQ][2];
  float lane_block_row_sum_old[kWarpTileSeqLenQ][2];
  fill_2D_regs<float, kWarpTileSeqLenQ, 2>(lane_block_row_max_old, -INFINITY);
  fill_2D_regs<float, kWarpTileSeqLenQ, 2>(lane_block_row_sum_old, 0.0f);
  // m[Br], l[Br], for the output of P[Br,Bc]=Q[Br,d]@K^T[d,Bc],
  // 64x(4)x4=1024 bytes, 1M+1M=2M. TODO: 64x4=256, may use each 
  // thread to store a max/sum value instead of using shared memory 
  // and mapping based on thread ID and row number in Br.
  static __shared__ float block_row_max_new_smem[Br][kMmaTileSeqLenK]; 
  static __shared__ float block_row_sum_new_smem[Br][kMmaTileSeqLenK];
  
  // ---------------------- Registers for S=Q@K^T/O=P@V ----------------------------
  // registers for QKV, S=Q[Br,d]@K[Bc,d]=[Br,Bc] and O=P[Br,Bc]@V[Bc,d]=[Br,d].
  uint32_t R_Q[ kWarpTileSeqLenQ][4];
  uint32_t R_K[ kWarpTileSeqLenK][2];
  uint32_t R_V[kWarpTileHeadDimV][2];
  // registers for current tile_K_seqlen within, [64,64] = S_tile[Br,Bc]
  // = Q_tile[Br,d] * K[Bc,d], each thread hold 2x32 bits regs.
  uint32_t R_S[kWarpTileSeqLenQ][ kWarpTileSeqLenK][2]; // [2][2][2]
  // registers for tile_K_seqlen O=PV[Br,d]=P@V, [2][2/4][2], 8 or 16 regs.
  // TODO: may reuse R_D as R_O? kWarpTileSeqLenP=kWarpTileSeqLenQ.
  uint32_t R_O[kWarpTileSeqLenP][kWarpTileHeadDimV][2]; // [2][2/4][2]
  // registers final Output [D]=final rescale(R_O), [2][2/4][2], 8 or 16 regs.
  uint32_t R_D[kWarpTileSeqLenP][kWarpTileHeadDimV][2]; // [2][2/4][2]
  fill_3D_regs<uint32_t, kWarpTileSeqLenQ, kWarpTileSeqLenK,  2>(R_S, 0);
  fill_3D_regs<uint32_t, kWarpTileSeqLenP, kWarpTileHeadDimV, 2>(R_D, 0);
  fill_3D_regs<uint32_t, kWarpTileSeqLenP, kWarpTileHeadDimV, 2>(R_O, 0);
  FA_MMA_PRINT_T0_REG(R_O[0][0][0], "Init R_O tile");
  FA_MMA_PRINT_T0_REG(R_D[0][0][0], "Init R_D tile");
  FA_MMA_PRINT_T0_REG(R_S[0][0][0], "Init R_S tile");

  // load Q from gmem -> smem, only load once.
  {
    int load_gmem_Q_d = load_smem_Q_d;
    int load_gmem_Q_addr = (Q_gmem_offset + load_gmem_Q_Br * kHeadDim + load_gmem_Q_d);
    uint32_t load_smem_Q_ptr = (smem_Q_base_ptr + (
      load_smem_Q_Br * (kHeadDim + kPad) + load_smem_Q_d) * sizeof(half));
    #pragma unroll
    for (int i = 0; i < (kHeadDim / (KNumThreads / Br)); i += 8) {
      CP_ASYNC_CG(load_smem_Q_ptr + i * 2, &Q[load_gmem_Q_addr + i], 16);
    }
    CP_ASYNC_COMMIT_GROUP();
  }

  // load K from gmem -> smem, (kStage - 1) K^T tiles, [d,Bc]
  if constexpr (kStage > 1) {
    #pragma unroll
    for (int stage = 0; stage < (kStage - 1); ++stage) {
      // update the offset of n according to stages
      load_gmem_K_Bc_offset += stage * Bc; // s2, +offset 0
      int load_gmem_K_d  = load_smem_K_d; // K^T [d,Bc] from [d,seqlen]
      int load_gmem_K_Bc = load_gmem_K_Bc_offset + load_smem_K_Bc; // < seqlen
      int load_gmem_K_addr = (K_gmem_offset + load_gmem_K_d * QKV_seqlen + load_gmem_K_Bc);
      uint32_t load_smem_K_ptr = (
        smem_K_base_ptr + (stage * K_tile_size + 
                           load_smem_K_d * (Bc + kPad) + 
                           load_smem_K_Bc) * sizeof(half));
      #pragma unroll
      for (int i = 0; i < (Bc / (KNumThreads / kHeadDim)); i += 8) {
        CP_ASYNC_CG(load_smem_K_ptr + i * 2, &K[load_gmem_K_addr + i], 16);
      }
      CP_ASYNC_COMMIT_GROUP();
    }
  } else {
    // kStage = 1
      load_gmem_K_Bc_offset += 0 * Bc; 
      int load_gmem_K_d  = load_smem_K_d; // load K^T [d,Bc] from [d,seqlen]
      int load_gmem_K_Bc = load_gmem_K_Bc_offset + load_smem_K_Bc; // < seqlen
      int load_gmem_K_addr = (K_gmem_offset + load_gmem_K_d * QKV_seqlen + load_gmem_K_Bc);
      uint32_t load_smem_K_ptr = (
        smem_K_base_ptr + (load_smem_K_d * (Bc + kPad) + 
                           load_smem_K_Bc) * sizeof(half));
      #pragma unroll
      for (int i = 0; i < (Bc / (KNumThreads / kHeadDim)); i += 8) {
        CP_ASYNC_CG(load_smem_K_ptr + i * 2, &K[load_gmem_K_addr + i], 16);
      }
      CP_ASYNC_COMMIT_GROUP();
  }

  // wait Q and at least (kStage - 1) for K ready.
  if constexpr (kStage - 2 >= 0) {
    CP_ASYNC_WAIT_GROUP(kStage - 2); // s2->0, s3->1, s4->2
  } else {
    CP_ASYNC_WAIT_GROUP(0);
  }
  __syncthreads(); 

  // <loop over K seqlen>: for K^T[d,seqlen] with K^T_tile[d,Bc]
  // tile_K_seqlen: compute S_tile[Br,Bc] = Q@K^T = Q_tile[Br,d] * K^T[d,Bc]
  #pragma unroll 1
  for (int tile_K_seqlen = 0; tile_K_seqlen < Tc; ++tile_K_seqlen) { 
    // TODO: process last tile_K_seqlen ? pad to multiple of 8.
    // s2 tn 0->0, 1->1, 2->0; s3 tn 0->0, 1->1, 2->2, 3->0;
    int smem_sel      = (tile_K_seqlen) % kStage;   
    // s2 tn 0->1, 1->0, 2->1; s3 tn 0->2, 1->0, 2->1, 3->2;  
    int smem_sel_next = (tile_K_seqlen + (kStage - 1)) % kStage;
    // multi stages pipeling gmem -> smem
    // NOTE: kStage must be > 1 for pipeling. For s1, smem_sel 
    // and smem_sel_next will always equal 0, thus, we can not 
    // prefetch KV from gmem to smem before tile_K_seqlen MMA done.
    // Prefetch curr V tile_K_seqlen [Bc,d] (no stages)
    {
      load_gmem_V_Bc_offset += tile_K_seqlen * Bc;
      int load_gmem_V_Bc = load_gmem_V_Bc_offset + load_smem_V_Bc;
      int load_gmem_V_d  = load_smem_V_d;
      int load_gmem_V_addr = (
        V_gmem_offset + load_gmem_V_Bc * kHeadDim + load_gmem_V_d);
      uint32_t load_smem_V_ptr = (
        smem_V_base_ptr + (load_smem_V_Bc * (kHeadDim + kPad) + 
                           load_smem_V_d) * sizeof(half)
      );
      #pragma unroll
      for (int i = 0; i < (kHeadDim / (KNumThreads / Bc)); i += 8) {
        CP_ASYNC_CG(load_smem_V_ptr + i * 2, &V[load_gmem_V_addr + i], 16);
      }
      CP_ASYNC_COMMIT_GROUP();
    }
    // Prefetch next stage K (tile_K_seqlen + 1) [d,Bc]
    if constexpr (kStage > 1) {
      if ((tile_K_seqlen + 1) < Tc) {
        load_gmem_K_Bc_offset += (tile_K_seqlen + 1) * Bc;
        int load_gmem_K_d  = load_smem_K_d; // load K^T [d,Bc] from [d,seqlen]
        int load_gmem_K_Bc = load_gmem_K_Bc_offset + load_smem_K_Bc;
        int load_gmem_K_addr = (
          K_gmem_offset + load_gmem_K_d * QKV_seqlen + load_gmem_K_Bc);
        uint32_t load_smem_K_ptr = (
          smem_K_base_ptr + (smem_sel_next * K_tile_size + 
                             load_smem_K_d * (Bc + kPad) + 
                             load_smem_K_Bc) * sizeof(half)
        );
        #pragma unroll
        for (int i = 0; i < (Bc / (KNumThreads / kHeadDim)); i += 8) {
          CP_ASYNC_CG(load_smem_K_ptr + i * 2, &K[load_gmem_K_addr + i], 16);
        }
        CP_ASYNC_COMMIT_GROUP();
      } else {
        // wait all memory issues ready for last tile. (may not need)
        CP_ASYNC_WAIT_GROUP(0);
        __syncthreads(); 
      }
    }
    
    // <loop over K d>: tile_K_d, kMmaAtomK = 16, K_tile_d[kMmaAtomK,Bc]
    // Matmul with NN layout, Q row major, K row major. 
    // S_tile[Br,Bc]=Q_tile[Br,d]@K[d,Bc]
    #pragma unroll
    for (int tile_K_d = 0; tile_K_d < (kHeadDim / kMmaAtomK); ++tile_K_d) {
      // smem -> reg, load m16k16 smem Q, offset d according tile_K_d.
      // ldmatrix.x4 for Q_tile_smem.
      #pragma unroll
      for (int i = 0; i < kWarpTileSeqLenQ; ++i) { // Q[Br,d]=[M,K]
        int warp_smem_Q_Br = warp_QP * (kMmaAtomM * kWarpTileSeqLenQ) + i * kMmaAtomM;
        int lane_smem_Q_Br = warp_smem_Q_Br + lane_id % 16; // 0~15
        int lane_smem_Q_d  = tile_K_d * kMmaAtomK + (lane_id / 16) * 8; // 0,8
        uint32_t lane_smem_Q_ptr = (
            smem_Q_base_ptr + (lane_smem_Q_Br * (kHeadDim + kPad) + 
                               lane_smem_Q_d) * sizeof(half)
        );
        LDMATRIX_X4(R_Q[i][0], R_Q[i][1], R_Q[i][2], R_Q[i][3], 
                    lane_smem_Q_ptr); // now, R_Q
      }
      // smem -> reg, load k16n8 from smem K, offset d according tile_K_d.
      // ldmatrix.x2.trans for K_tile_smem, [kMmaAtomK,Bc] from [d,Bc]=[K,N]
      #pragma unroll
      for (int j = 0; j < kWarpTileSeqLenK; ++j) {
        int warp_smem_K_Bc = warp_KV * (kMmaAtomN * kWarpTileSeqLenK) + j * kMmaAtomN;  // (N)
        int lane_smem_K_d  = tile_K_d * kMmaAtomK + lane_id % 16; // 0~15 (K);
        int lane_smem_K_Bc = warp_smem_K_Bc; // 0(N)
        uint32_t lane_smem_K_ptr = (
            smem_K_base_ptr + (smem_sel * K_tile_size + 
                               lane_smem_K_d * (Bc + kPad) + 
                               lane_smem_K_Bc) * sizeof(half)
        );
        LDMATRIX_X2_T(R_K[j][0], R_K[j][1], lane_smem_K_ptr); // R_K
      } // end for kWarpTileSeqLenK

      FA_MMA_PRINT_T0_REG(R_K[0][0], "Load K s->r, tile_K_seqlen: %d, tile_K_d: %d", 
                          tile_K_seqlen, tile_K_d);

      // MMA compute
      #pragma unroll
      for (int i = 0; i < kWarpTileSeqLenQ; ++i) {
        #pragma unroll
        for (int j = 0; j < kWarpTileSeqLenK; ++j) {
          HMMA16816(R_S[i][j][0], R_S[i][j][1], 
                    R_Q[i][0],    R_Q[i][1],    R_Q[i][2], R_Q[i][3], 
                    R_K[j][0],    R_K[j][1], 
                    R_S[i][j][0], R_S[i][j][1]);
        }
      }
    } // end loop over d, S=Q@K^T
    __syncthreads();
    // R_S[2][2][2]
    FA_MMA_PRINT_REG(R_S[0][0][0], "MMA Q@K^T, R_S[0][0][0], tile_K_seqlen: %d, tid: %d, lane: %d", tile_K_seqlen, tid, lane_id);
    FA_MMA_PRINT_REG(R_S[0][0][1], "MMA Q@K^T, R_S[0][0][1], tile_K_seqlen: %d, tid: %d, lane: %d", tile_K_seqlen, tid, lane_id);
    FA_MMA_PRINT_REG(R_S[0][1][0], "MMA Q@K^T, R_S[0][1][0], tile_K_seqlen: %d, tid: %d, lane: %d", tile_K_seqlen, tid, lane_id);
    FA_MMA_PRINT_REG(R_S[0][1][1], "MMA Q@K^T, R_S[0][1][1], tile_K_seqlen: %d, tid: %d, lane: %d", tile_K_seqlen, tid, lane_id);
    FA_MMA_PRINT_REG(R_S[1][0][0], "MMA Q@K^T, R_S[1][0][0], tile_K_seqlen: %d, tid: %d, lane: %d", tile_K_seqlen, tid, lane_id);
    FA_MMA_PRINT_REG(R_S[1][0][1], "MMA Q@K^T, R_S[1][0][1], tile_K_seqlen: %d, tid: %d, lane: %d", tile_K_seqlen, tid, lane_id);
    FA_MMA_PRINT_REG(R_S[1][1][0], "MMA Q@K^T, R_S[1][1][0], tile_K_seqlen: %d, tid: %d, lane: %d", tile_K_seqlen, tid, lane_id);
    FA_MMA_PRINT_REG(R_S[1][1][1], "MMA Q@K^T, R_S[1][1][1], tile_K_seqlen: %d, tid: %d, lane: %d", tile_K_seqlen, tid, lane_id);

    // TODO: May reuse K smem for V, for example, stages 2, stage
    // 0 K smem can be reuse as V smem 0 because we do not need 
    // K values on stage 0 K smem anymore.

    // Now, we got a computed tile of S[Br,N], tile with shape [Br,Bc].
    // Assume [Br, Bc] = [64, 64] = 64x64 = 4096 values. Each thread holds
    // a portion of this [Br, Bc] block, specifically, R_S = R_S[2][2][2]. 
    // This means that each Warp (MMA) repeats 2 times in the N direction 
    // for both Q and K, resulting in 2x2 = 4 sets of MMA results. Each set 
    // of results is stored in 2 32-bit registers, with each register holding 
    // 2 half-precision values. In other words, each thread stores (4x2)x2 = 16 
    // half-precision values. With a total of 256 threads, the total number of 
    // half-precision values is 256x16 = 4096, which exactly matches the total 
    // [Br, Bc] = [64, 64] values.

    // The layout of 8 MMA m16n8k16 (2x4)  [after] kWarpTileQPxkWarpTileKV(2x2) -> 32x2,32x2=64x64: 
    // |  [64,64]  |    warp_KV 0    |    warp_KV 1    |    warp_KV 2    |    warp_KV 3    |
    // | warp_QP 0 |-- MMA 0,MMA 0 --|-- MMA 2,MMA 2 --|-- MMA 4,MMA 4 --|-- MMA 6,MMA 6 --| row max
    // | warp_QP 0 |-- MMA 0,MMA 0 --|-- MMA 2,MMA 2 --|-- MMA 4,MMA 4 --|-- MMA 6,MMA 6 --| row max
    // | warp_QP 1 |-- MMA 1,MMA 1 --|-- MMA 3,MMA 3 --|-- MMA 5,MMA 5 --|-- MMA 7,MMA 7 --| row max
    // | warp_QP 1 |-- MMA 1,MMA 1 --|-- MMA 3,MMA 3 --|-- MMA 5,MMA 5 --|-- MMA 7,MMA 7 --| row max

    // WIP: online safe softmax, warp/block reduce max/sum, row wise
    // warp 0/2/4/6, [0][2] row 0~15,  col 0/8/16/32, max, [1][2] row 16~31, col 0/8/16/32, max
    // warp 1/3/5/7, [0][2] row 32~47, col 0/8/16/32, max, [1][2] row 48~61, col 0/8/16/32, max
    float lane_row_max_new[kWarpTileSeqLenQ][2]; 
    float lane_row_sum_new[kWarpTileSeqLenQ][2]; 
    fill_2D_regs<float, kWarpTileSeqLenQ, 2>(lane_row_max_new, -INFINITY);
    fill_2D_regs<float, kWarpTileSeqLenQ, 2>(lane_row_sum_new, 0.0f);

    // Row max for [Br,Bc] tile, Thread -> Warp -> Block.
    #pragma unroll 1
    for (int i = 0; i < kWarpTileSeqLenQ; ++i) {
      // Thread level reduce max across kWarpTileSeqLenK dim, namely Bc.
      #pragma unroll
      for (int j = 0; j < kWarpTileSeqLenK; ++j) {
        // reference: https://docs.nvidia.com/cuda/parallel-thread-execution/index.html
        // #matrix-fragments-for-mma-m16n8k16-with-floating-point-type
        // The layout of the fragments held by different threads for C. (m16n8k16)
        // Row\Col  0    1    2    3    4    5    6    7
        // 0        T0: {c0, c1}  T1: {c0, c1}  T2: {c0, c1}  T3: {c0, c1}
        // 1        T4: {c0, c1}  T5: {c0, c1}  T6: {c0, c1}  T7: {c0, c1}
        // 2        ...
        // ...
        // 7        T28: {c0, c1}  T29: {c0, c1}  T30: {c0, c1}  T31: {c0, c1}
        // 8        T0: {c2, c3}   T1: {c2, c3}   T2: {c2, c3}   T3: {c2, c3}
        // 9        T4: {c2, c3}   T5: {c2, c3}   T6: {c2, c3}   T7: {c2, c3}
        // 10       ...
        // ...
        // 15       T28: {c2, c3}  T29: {c2, c3}  T30: {c2, c3}  T31: {c2, c3}
        float2 t_reg_S_0 = __half22float2(HALF2(R_S[i][j][0])); // 0~7  {c0, c1}
        float2 t_reg_S_1 = __half22float2(HALF2(R_S[i][j][1])); // 8~15 {c2, c3}
        // This should be the row max after S = (Q @ K^T) / sqrt(d)
        float tmp_max_0 = max(t_reg_S_0.x, t_reg_S_0.y) * scale;
        float tmp_max_1 = max(t_reg_S_1.x, t_reg_S_1.y) * scale;
        lane_row_max_new[i][0] = max(lane_row_max_new[i][0], tmp_max_0);
        lane_row_max_new[i][1] = max(lane_row_max_new[i][1], tmp_max_1);
      } // end for kWarpTileSeqLenK

      // Warp level reduce max, warp_size = 4
      // Each thread contains the maximum of 2 rows of Br, 
      // and only the values of T0, T4, ..., T28 are used.
      // Br, row_id = warp_QP<0|1> * 32 + i<0|1> * 16 + 0 * 8 + (lane / 4) <0~7>
      lane_row_max_new[i][0] = warp_reduce_max<float, 4>(lane_row_max_new[i][0]);
      // Br, row_id = warp_QP<0|1> * 32 + i<0|1> * 16 + 1 * 8 + (lane / 4) <8~15>
      lane_row_max_new[i][1] = warp_reduce_max<float, 4>(lane_row_max_new[i][1]);

      if (lane_id % 4 == 0) { // only need T0,T4,...,T28
        block_row_max_new_smem[ // Br, row_id, 0~7,  16~23, 32~39, 48~55
          warp_QP * 32 + i * 16 + 0 * 8 + (lane_id / 4)][warp_KV] = lane_row_max_new[i][0];
        block_row_max_new_smem[ // Br, row_id, 8~15, 24~31, 40~47, 56~63
          warp_QP * 32 + i * 16 + 1 * 8 + (lane_id / 4)][warp_KV] = lane_row_max_new[i][1];
      }
    } // end for kWarpTileSeqLenQ
    __syncthreads();

    // Block level reduce max, row wise, 64x4=256
    float wrp_row_max_new = (
      block_row_max_new_smem[tid / kMmaTileSeqLenK][tid % kMmaTileSeqLenK]); // [0~63][0~4]
    float blk_row_max_new = warp_reduce_max<float, 4>(wrp_row_max_new);
    block_row_max_new_smem[tid / kMmaTileSeqLenK][tid % kMmaTileSeqLenK] = (
      blk_row_max_new);
    __syncthreads();
    // Exp sum and mul scale_factor for [Br,Bc] tile, Thread -> Warp -> Block.
    #pragma unroll
    for (int i = 0; i < kWarpTileSeqLenQ; ++i) {
      // Use latest global row max without update.
      // Br 0, row_id, 0~7,  16~23, 32~39, 48~55; 
      float block_row_max_new_0 = block_row_max_new_smem[
        warp_QP * 32 + i * 16 + 0 * 8 + (lane_id / 4)][0]; 
      // Br 1, row_id, 8~15, 24~31, 40~47, 56~63;
      float block_row_max_new_1 = block_row_max_new_smem[
        warp_QP * 32 + i * 16 + 1 * 8 + (lane_id / 4)][0];
      block_row_max_new_0 = (tile_K_seqlen > 0 ?
                             max(lane_block_row_max_old[i][0], block_row_max_new_0) : 
                             block_row_max_new_0);
      block_row_max_new_1 = (tile_K_seqlen > 0 ? 
                             max(lane_block_row_max_old[i][1],  block_row_max_new_1) : 
                             block_row_max_new_1);
      #pragma unroll
      for (int j = 0; j < kWarpTileSeqLenK; ++j) {
        float2 t_reg_S_0 = __half22float2(HALF2(R_S[i][j][0])); // 0~7  {c0, c1}
        float2 t_reg_S_1 = __half22float2(HALF2(R_S[i][j][1])); // 8~15 {c2, c3}
        t_reg_S_0.x = __expf(t_reg_S_0.x * scale - block_row_max_new_0);
        t_reg_S_0.y = __expf(t_reg_S_0.y * scale - block_row_max_new_0);
        t_reg_S_1.x = __expf(t_reg_S_1.x * scale - block_row_max_new_1);
        t_reg_S_1.y = __expf(t_reg_S_1.y * scale - block_row_max_new_1);
        lane_row_sum_new[i][0] += (t_reg_S_0.x + t_reg_S_0.y);
        lane_row_sum_new[i][1] += (t_reg_S_1.x + t_reg_S_1.y);
        // Update R_S for P[Br,Bc] = Exp(S-m), point wise.
        HALF2(R_S[i][j][0]) = __float22half2_rn(t_reg_S_0);
        HALF2(R_S[i][j][1]) = __float22half2_rn(t_reg_S_1);
      } // end for kWarpTileSeqLenK

      // Warp level reduce sum, warp_size = 4
      lane_row_sum_new[i][0] = warp_reduce_sum<float, 4>(lane_row_sum_new[i][0]);
      lane_row_sum_new[i][1] = warp_reduce_sum<float, 4>(lane_row_sum_new[i][1]);

      if (lane_id % 4 == 0) { // only need T0,T4,...,T28
        block_row_sum_new_smem[ // Br, row_id, 0~7,  16~23, 32~39, 48~55
          warp_QP * 32 + i * 16 + 0 * 8 + (lane_id / 4)][warp_KV] = lane_row_sum_new[i][0];
        block_row_sum_new_smem[ // Br, row_id, 8~15, 24~31, 40~47, 56~63
          warp_QP * 32 + i * 16 + 1 * 8 + (lane_id / 4)][warp_KV] = lane_row_sum_new[i][1];
      }
    } // end for kWarpTileSeqLenQ
    __syncthreads();

    // Block level reduce sum, row wise, 64x4=256
    float wrp_row_sum_new = (
      block_row_sum_new_smem[tid / kMmaTileSeqLenK][tid % kMmaTileSeqLenK]); // [0~63][0~4]
    float blk_row_sum_new = warp_reduce_sum<float, 4>(wrp_row_sum_new);
    block_row_sum_new_smem[tid / kMmaTileSeqLenK][tid % kMmaTileSeqLenK] = (
      blk_row_sum_new);
    __syncthreads();

    // Compute P[Br,Bc] @ V[Bc,d] = [Br,d] = [64, 64/128], partion Attention.
    // Here, we have to wait V ready before compute O = P @ V
    if constexpr (kStage == 2) {
      // NOTE: we have send V mem issues before K
      CP_ASYNC_WAIT_GROUP(1); // s1->-1, s2->0, s3->1, s4->2
    } else {
      CP_ASYNC_WAIT_GROUP(0);
    }
    __syncthreads(); 
    
    // Retile warp for [Br,d], kWarpTileHeadDimV: 1=32/(4*8); 2=64/(4*8); 4=128/(4*8).
    // Compute P[Br,Bc] @ V[Bc,d] = [Br,d] = [64, 64/128], partion Attention.

    // If headdim=<32>, then, kWarpTileHeadDimV = 1, the layout of 8 MMA m16n8k16 (2x4) after 
    // kWarpTilePxkWarpTileV(2x1) tiling to (32x2,32x1)=(64x32), will look like: 
    // |  [64,32]  | warp_KV 0 | warp_KV 1 | warp_KV 2 | warp_KV 3 |
    // | warp_QP 0 |-- MMA 0 --|-- MMA 2 --|-- MMA 4 --|-- MMA 6 --|
    // | warp_QP 0 |-- MMA 0 --|-- MMA 2 --|-- MMA 4 --|-- MMA 6 --|
    // | warp_QP 1 |-- MMA 1 --|-- MMA 3 --|-- MMA 5 --|-- MMA 7 --|
    // | warp_QP 1 |-- MMA 1 --|-- MMA 3 --|-- MMA 5 --|-- MMA 7 --|

    // If headdim=<64>, then, kWarpTileHeadDimV = 2, the layout of 8 MMA m16n8k16 (2x4) after 
    // kWarpTilePxkWarpTileV(2x2) tiling to (32x2,32x2)=(64x64), will look like: 
    // |  [64,64]  |    warp_KV 0    |    warp_KV 1    |    warp_KV 2    |    warp_KV 3    |
    // | warp_QP 0 |-- MMA 0,MMA 0 --|-- MMA 2,MMA 2 --|-- MMA 4,MMA 4 --|-- MMA 6,MMA 6 --|
    // | warp_QP 0 |-- MMA 0,MMA 0 --|-- MMA 2,MMA 2 --|-- MMA 4,MMA 4 --|-- MMA 6,MMA 6 --|
    // | warp_QP 1 |-- MMA 1,MMA 1 --|-- MMA 3,MMA 3 --|-- MMA 5,MMA 5 --|-- MMA 7,MMA 7 --|
    // | warp_QP 1 |-- MMA 1,MMA 1 --|-- MMA 3,MMA 3 --|-- MMA 5,MMA 5 --|-- MMA 7,MMA 7 --|

    // If headdim=<128>, then, kWarpTileHeadDimV = 4, the layout of 8 MMA m16n8k16 (2x4) after 
    // kWarpTilePxkWarpTileV(2x2x2) tiling to (32x2,32x2x2)=(64x64x2), will look like: 
    // | [64,64x2] |         warp_KV 0           |           warp_KV 1         |           warp_KV 2         |          warp_KV 3          |
    // | warp_QP 0 |-- MMA 0,MMA 0,MMA 0,MMA 0 --|-- MMA 2,MMA 2,MMA 2,MMA 2 --|-- MMA 4,MMA 4,MMA 4,MMA 4 --|-- MMA 6,MMA 6,MMA 6,MMA 6 --|
    // | warp_QP 0 |-- MMA 0,MMA 0,MMA 0,MMA 0 --|-- MMA 2,MMA 2,MMA 2,MMA 2 --|-- MMA 4,MMA 4,MMA 4,MMA 4 --|-- MMA 6,MMA 6,MMA 6,MMA 6 --|
    // | warp_QP 1 |-- MMA 1,MMA 1,MMA 1,MMA 1 --|-- MMA 3,MMA 3,MMA 3,MMA 3 --|-- MMA 5,MMA 5,MMA 5,MMA 5 --|-- MMA 7,MMA 7,MMA 7,MMA 7 --|
    // | warp_QP 1 |-- MMA 1,MMA 1,MMA 1,MMA 1 --|-- MMA 3,MMA 3,MMA 3,MMA 3 --|-- MMA 5,MMA 5,MMA 5,MMA 5 --|-- MMA 7,MMA 7,MMA 7,MMA 7 --|
    
    // <loop over V Bc>: P[Br,Bc]@V[Bc,d]=[Br,d]=[64,64/128], partion Attention.
    // Matmul with NN layout: P[Br,Bc] row major, V[Bc,d] row major.
    // Make sure to clear the states in R_O before MMA for P@V for each step.
    fill_3D_regs<uint32_t, kWarpTileSeqLenP, kWarpTileHeadDimV, 2>(R_O, 0);
    #pragma unroll
    for (int tile_V_Bc = 0; tile_V_Bc < (Bc / kMmaAtomK); ++tile_V_Bc) {
      // Load k16n8 V from smem -> regs, R_KV, ldmatrix.x2.trans.
      #pragma unroll
      for (int j = 0; j < kWarpTileHeadDimV; ++j) { 
        int warp_smem_V_d  = warp_KV * (kMmaAtomN * kWarpTileHeadDimV) + j * kMmaAtomN; // d, matmaul N
        int lane_smem_V_Bc = tile_V_Bc * kMmaAtomK + lane_id % 16; // 0~15; Bc, matmul K
        int lane_smem_V_d  = warp_smem_V_d; // 0
        uint32_t lane_smem_V_ptr = (
            smem_V_base_ptr + (lane_smem_V_Bc * (kHeadDim + kPad) + 
                               lane_smem_V_d) * sizeof(half)
        );
        LDMATRIX_X2_T(R_V[j][0], R_V[j][1], lane_smem_V_ptr); // R_V
      }
        
      // values for P[Br,Bc] already in R_S registers.
      #pragma unroll 1
      for (int i = 0; i < kWarpTileSeqLenP; ++i) { // kWarpTileSeqLenQ=2
        #pragma unroll
        for (int j = 0; j < kWarpTileHeadDimV; ++j) {
#if defined(FLASH_ATTN_MMA_DEBUG) && defined(FLASH_ATTN_MMA_DEBUG_MORE)
          if (tid < 32) {
            FA_MMA_PRINT_REG(R_S[i][0][0], "[Before] R_S[%d][0][0] MMA P@V, tile_K_seqlen: %d, tid: %d, lane: %d", i, tile_K_seqlen, tid, lane_id); 
            FA_MMA_PRINT_REG(R_S[i][0][1], "[Before] R_S[%d][0][1] MMA P@V, tile_K_seqlen: %d, tid: %d, lane: %d", i, tile_K_seqlen, tid, lane_id); 
            FA_MMA_PRINT_REG(R_S[i][1][0], "[Before] R_S[%d][1][0] MMA P@V, tile_K_seqlen: %d, tid: %d, lane: %d", i, tile_K_seqlen, tid, lane_id); 
            FA_MMA_PRINT_REG(R_S[i][1][1], "[Before] R_S[%d][1][1] MMA P@V, tile_K_seqlen: %d, tid: %d, lane: %d", i, tile_K_seqlen, tid, lane_id); 
            FA_MMA_PRINT_REG(R_V[j][0], "[Before] R_V[%d][0] MMA P@V, tile_K_seqlen: %d, tid: %d, lane: %d", j, tile_K_seqlen, tid, lane_id); 
            FA_MMA_PRINT_REG(R_V[j][1], "[Before] R_V[%d][1] MMA P@V, tile_K_seqlen: %d, tid: %d, lane: %d", j, tile_K_seqlen, tid, lane_id); 
          }
#endif
          HMMA16816(R_O[i][j][0], R_O[i][j][1], 
                    R_S[i][0][0], R_S[i][0][1], R_S[i][1][0], R_S[i][1][1], 
                    R_V[j][0],    R_V[j][1],
                    R_O[i][j][0], R_O[i][j][1]);
        }
      }
    } // end for V Bc.

#if defined(FLASH_ATTN_MMA_DEBUG) && defined(FLASH_ATTN_MMA_DEBUG_MORE)
    if (tid < 32) {
      FA_MMA_PRINT_REG(R_O[0][0][0], "MMA P@V, R_O[0][0][0], tile_K_seqlen: %d, tid: %d, lane: %d", tile_K_seqlen, tid, lane_id);
      FA_MMA_PRINT_REG(R_O[0][0][1], "MMA P@V, R_O[0][0][1], tile_K_seqlen: %d, tid: %d, lane: %d", tile_K_seqlen, tid, lane_id);
      FA_MMA_PRINT_REG(R_O[0][1][0], "MMA P@V, R_O[0][1][0], tile_K_seqlen: %d, tid: %d, lane: %d", tile_K_seqlen, tid, lane_id);
      FA_MMA_PRINT_REG(R_O[0][1][1], "MMA P@V, R_O[0][1][1], tile_K_seqlen: %d, tid: %d, lane: %d", tile_K_seqlen, tid, lane_id);
      FA_MMA_PRINT_REG(R_O[1][0][0], "MMA P@V, R_O[1][0][0], tile_K_seqlen: %d, tid: %d, lane: %d", tile_K_seqlen, tid, lane_id);
      FA_MMA_PRINT_REG(R_O[1][0][1], "MMA P@V, R_O[1][0][1], tile_K_seqlen: %d, tid: %d, lane: %d", tile_K_seqlen, tid, lane_id);
      FA_MMA_PRINT_REG(R_O[1][1][0], "MMA P@V, R_O[1][1][0], tile_K_seqlen: %d, tid: %d, lane: %d", tile_K_seqlen, tid, lane_id);
      FA_MMA_PRINT_REG(R_O[1][1][1], "MMA P@V, R_O[1][1][1], tile_K_seqlen: %d, tid: %d, lane: %d", tile_K_seqlen, tid, lane_id);
    }
#endif

    // Rescale O -> Update row sum Exp -> then, Update row max.
    #pragma unroll
    for (int i = 0; i < kWarpTileSeqLenP; ++i) { // kWarpTileSeqLenQ=kWarpTileSeqLenP
      // m = max(m_old, m_new), l = exp(m_old - m) * l_old + l_new (FA2 paper)
      // Br 0, row_id, 0~7,  16~23, 32~39, 48~55; Br 1, row_id, 8~15, 24~31, 40~47, 56~63
      float block_row_max_new_0 = block_row_max_new_smem[
        warp_QP * 32 + i * 16 + 0 * 8 + (lane_id / 4)][0];
      float block_row_max_new_1 = block_row_max_new_smem[
        warp_QP * 32 + i * 16 + 1 * 8 + (lane_id / 4)][0];
      float block_row_sum_new_0 = block_row_sum_new_smem[
        warp_QP * 32 + i * 16 + 0 * 8 + (lane_id / 4)][0];
      float block_row_sum_new_1 = block_row_sum_new_smem[
        warp_QP * 32 + i * 16 + 1 * 8 + (lane_id / 4)][0];
      float block_row_max_old_0 = lane_block_row_max_old[i][0];
      float block_row_max_old_1 = lane_block_row_max_old[i][1];
      block_row_max_new_0 = (tile_K_seqlen > 0 ? max(block_row_max_old_0, 
                                              block_row_max_new_0) : block_row_max_new_0);
      block_row_max_new_1 = (tile_K_seqlen > 0 ? max(block_row_max_old_1, 
                                              block_row_max_new_1) : block_row_max_new_1);
      block_row_max_old_0 = (tile_K_seqlen > 0 ? block_row_max_old_0 : block_row_max_new_0);                                       
      block_row_max_old_1 = (tile_K_seqlen > 0 ? block_row_max_old_0 : block_row_max_new_1);                                       

      // 0. Rescale O: Online rescaling O each tile_K_seqlen step, need m_new, m_old.
      // m = max(m_old, m_new), O_new[Br,d] = ( 1/exp(m_old - m) ) * O_old + P@V (FA2 paper)
      #pragma unroll
      for (int j = 0; j < kWarpTileHeadDimV; ++j) {
        float2 t_reg_O_0 = __half22float2(HALF2(R_O[i][j][0])); // 0~7  {c0, c1}
        float2 t_reg_O_1 = __half22float2(HALF2(R_O[i][j][1])); // 8~15 {c2, c3}
        float2 t_reg_D_0 = __half22float2(HALF2(R_D[i][j][0])); // 0~7  {c0, c1}
        float2 t_reg_D_1 = __half22float2(HALF2(R_D[i][j][1])); // 8~15 {c2, c3}
        float rescale_o_factor_0 = __expf(block_row_max_new_0 - block_row_max_old_0);
        float rescale_o_factor_1 = __expf(block_row_max_new_1 - block_row_max_old_1);
        t_reg_D_0.x = rescale_o_factor_0 * t_reg_D_0.x + t_reg_O_0.x;
        t_reg_D_0.y = rescale_o_factor_0 * t_reg_D_0.y + t_reg_O_0.y;
        t_reg_D_1.x = rescale_o_factor_1 * t_reg_D_1.x + t_reg_O_1.x;
        t_reg_D_1.y = rescale_o_factor_1 * t_reg_D_1.y + t_reg_O_1.y;
        HALF2(R_D[i][j][0]) = __float22half2_rn(t_reg_D_0);
        HALF2(R_D[i][j][1]) = __float22half2_rn(t_reg_D_1);
      } // end for kWarpTileHeadDimV.

      // Now, we can update m, l after O has been scaled.
      // 1. First, update block row sum Exp for each lane which
      // need both m_new and m_old.
      float block_row_sum_old_0 = lane_block_row_sum_old[i][0];
      float block_row_sum_old_1 = lane_block_row_sum_old[i][1];
      lane_block_row_sum_old[i][0] = (
        __expf(block_row_max_new_0 - block_row_max_old_0) * block_row_sum_old_0 
        + block_row_sum_new_0);
      lane_block_row_sum_old[i][1] = (
        __expf(block_row_max_new_1 - block_row_max_old_1) * block_row_sum_old_1 
        + block_row_sum_new_1);
      // 2. Then, update block row max for each lane.
      lane_block_row_max_old[i][0] = block_row_max_new_0;
      lane_block_row_max_old[i][1] = block_row_max_new_1;
    }

    FA_MMA_PRINT_T0_REG(R_D[0][0][0], "After Scale O tile, R_D[0][0][0]");
  
    // NOTE: After compute P @ V, we have to wait next K tile ready in smem.
    // do not need to wait any things if kStage == 1.
    if constexpr (kStage == 2) {
      CP_ASYNC_WAIT_GROUP(0);
      __syncthreads(); 
    }

  } // end loop over N
  __syncthreads();

  // Finaly, we still have to rescale O once more.
  // O_output(D) = ( 1/l_final ) * O_final (FA2 paper)
  #pragma unroll
  for (int i = 0; i < kWarpTileSeqLenP; ++i) {
    #pragma unroll
    for (int j = 0; j < kWarpTileHeadDimV; ++j) {
      float2 t_reg_D_0 = __half22float2(HALF2(R_D[i][j][0])); // 0~7  {c0, c1}
      float2 t_reg_D_1 = __half22float2(HALF2(R_D[i][j][1])); // 8~15 {c2, c3}
      t_reg_D_0.x = __frcp_rn(lane_block_row_sum_old[i][0]) * t_reg_D_0.x;
      t_reg_D_0.y = __frcp_rn(lane_block_row_sum_old[i][0]) * t_reg_D_0.y;
      t_reg_D_1.x = __frcp_rn(lane_block_row_sum_old[i][1]) * t_reg_D_1.x;
      t_reg_D_1.y = __frcp_rn(lane_block_row_sum_old[i][1]) * t_reg_D_1.y;
      HALF2(R_D[i][j][0]) = __float22half2_rn(t_reg_D_0);
      HALF2(R_D[i][j][1]) = __float22half2_rn(t_reg_D_1);
    }
  }

  FA_MMA_PRINT_T0_REG(R_D[0][0][0], "After Final ReScale O tile, R_D[0][0][0]");

  // Store O(D): Write O[Br,d] from regs -> gmem, collective store 
  // with reg reuse & warp shuffle. need R[2][4], may reuse 
  // R_Q[kWarpTileSeqLenQ][4]=[2][4].
  #pragma unroll 1
  for (int i = 0; i < kWarpTileSeqLenP; ++i) {
    #pragma unroll
    for (int j = 0; j < kWarpTileHeadDimV; ++j) {
      R_Q[0][0] = R_D[i][j][0]; R_Q[1][0] = R_D[i][j][1]; // warp_size 4
      R_Q[0][1] = __shfl_sync((0xffffffff), R_D[i][j][0], lane_id + 1);
      R_Q[0][2] = __shfl_sync((0xffffffff), R_D[i][j][0], lane_id + 2);
      R_Q[0][3] = __shfl_sync((0xffffffff), R_D[i][j][0], lane_id + 3);
      R_Q[1][1] = __shfl_sync((0xffffffff), R_D[i][j][1], lane_id + 1);
      R_Q[1][2] = __shfl_sync((0xffffffff), R_D[i][j][1], lane_id + 2);
      R_Q[1][3] = __shfl_sync((0xffffffff), R_D[i][j][1], lane_id + 3);

      // st.global.v4 128 bits.
      if (lane_id % 4 == 0) {
        int store_warp_regs_O_Br = warp_QP * (kMmaAtomM * kWarpTileSeqLenP ) + i * kMmaAtomM;
        int store_lane_gmem_O_Br = O_tile_id * Br + store_warp_regs_O_Br + lane_id / 4;
        int store_warp_regs_O_d  = warp_KV * (kMmaAtomN * kWarpTileHeadDimV) + j * kMmaAtomN;
        // The current tile actually covers all values in dimension d, therefore, 
        // there is no need to add a bx*BN term to calculate the offset, as you 
        // would in matrix multiplication.
        int store_lane_gmem_O_d = store_warp_regs_O_d;
        int store_gmem_O_addr_0 = (O_gmem_offset + (store_lane_gmem_O_Br + 0) * kHeadDim + 
                                   store_lane_gmem_O_d);
        int store_gmem_O_addr_1 = (O_gmem_offset + (store_lane_gmem_O_Br + 8) * kHeadDim + 
                                   store_lane_gmem_O_d);
        LDST128BITS(O[store_gmem_O_addr_0]) = LDST128BITS(R_Q[0][0]);
        LDST128BITS(O[store_gmem_O_addr_1]) = LDST128BITS(R_Q[1][0]);
        FA_MMA_PRINT_T0_REG(R_Q[0][0], "Store O, (n,d)=(%d,%d), (i,j)=(%d,%d)", 
                            store_lane_gmem_O_Br + 0, store_lane_gmem_O_d, i, j);
        FA_MMA_PRINT_T0_REG(R_Q[1][0], "Store O, (n,d)=(%d,%d) (i,j)=(%d,%d)", 
                            store_lane_gmem_O_Br + 8, store_lane_gmem_O_d, i, j);
      }
    } // end for kWarpTileHeadDimV
  } // end for kWarpTileSeqLenQ
}

// --------------------- PyTorch bindings for custom kernel -----------------------
#include <torch/types.h>
#include <torch/extension.h>
#define STRINGFY(str) #str
#define TORCH_BINDING_COMMON_EXTENSION(func) \
  m.def(STRINGFY(func), &func, STRINGFY(func));

#define CHECK_TORCH_TENSOR_DTYPE(T, th_type)                 \
if(((T).options().dtype() != (th_type))) {                   \
  std::cout << "Tensor Info:" << (T).options() << std::endl; \
  throw std::runtime_error("values must be "#th_type);       \
}

#define CHECK_TORCH_TENSOR_SHAPE(T1, T2)             \
if (((T2).size(0) != (T1).size(0)) ||                \
    ((T2).size(1) != (T1).size(1)) ||                \
    ((T2).size(2) != (T1).size(2)) ||                \
    ((T2).size(3) != (T1).size(3))) {                \
  throw std::runtime_error("Tensor size mismatch!"); \
}

template<const int kHeadDim, const int kStage>
void launch_flash_attn_mma(
  torch::Tensor Q, torch::Tensor K, torch::Tensor V, torch::Tensor O) {
  constexpr int kMmaAtomM = 16;
  constexpr int kMmaAtomN = 8;
  constexpr int kMmaAtomK = 16;
  constexpr int kMmaTileSeqLenQ = 2;
  constexpr int kMmaTileSeqLenP = 2;
  constexpr int kMmaTileSeqLenK = 4;
  constexpr int kMmaTileHeadDimV = 4;
  constexpr int kWarpTileSeqLenQ = 2;
  constexpr int kWarpTileSeqLenP = 2;
  constexpr int kWarpTileSeqLenK = 2;
  constexpr int kWarpTileHeadDimV = (kHeadDim / (kMmaAtomN*kMmaTileHeadDimV));
  constexpr int Br = kMmaAtomM * kMmaTileSeqLenQ * kWarpTileSeqLenQ; // 16*2*2=64
  constexpr int Bc = kMmaAtomN * kMmaTileSeqLenK * kWarpTileSeqLenK; // 8*4*2=64
  constexpr int kPad = 0;

  // Calculate SRAM size needed per block, Q,K,V smem size
  const int smem_max_size = ((Br * (kHeadDim + kPad)) + 
                             (kStage * kHeadDim * (Bc + kPad)) + 
                             (Bc * (kHeadDim + kPad))) * sizeof(half); 

  const int QKV_batch  = Q.size(0); 
  const int QKV_head   = Q.size(1);
  const int QKV_seqlen = Q.size(2); // QKV_seqlen
  assert(QKV_seqlen % Bc == 0); // multiple of Bc=64

  dim3 grid(QKV_batch, QKV_head, div_ceil(QKV_seqlen, Br)); // batch_size x num_heads x Tr(=N/Br)
  dim3 block(WARP_SIZE * kMmaTileSeqLenQ * kMmaTileSeqLenK); // 8 warps per block

  cudaFuncSetAttribute(
    flash_attn_mma_kernel<
      kHeadDim, 
      kMmaAtomM, 
      kMmaAtomN, 
      kMmaAtomK, 
      kMmaTileSeqLenQ, 
      kMmaTileSeqLenK, 
      kMmaTileSeqLenP, 
      kMmaTileHeadDimV, 
      kWarpTileSeqLenQ, 
      kWarpTileSeqLenK, 
      kWarpTileSeqLenP, 
      kWarpTileHeadDimV, 
      kStage, 
      kPad
    >,
    cudaFuncAttributeMaxDynamicSharedMemorySize,
    98304
  );

  flash_attn_mma_kernel<
    kHeadDim, 
    kMmaAtomM, 
    kMmaAtomN, 
    kMmaAtomK, 
    kMmaTileSeqLenQ,  
    kMmaTileSeqLenK,
    kMmaTileSeqLenP, 
    kMmaTileHeadDimV, 
    kWarpTileSeqLenQ, 
    kWarpTileSeqLenK, 
    kWarpTileSeqLenP, 
    kWarpTileHeadDimV, 
    kStage, 
    kPad
  ><<<grid, block, smem_max_size>>>(
    reinterpret_cast<half*>(Q.data_ptr()),
    reinterpret_cast<half*>(K.data_ptr()),
    reinterpret_cast<half*>(V.data_ptr()),
    reinterpret_cast<half*>(O.data_ptr()),
    QKV_seqlen
  );
}

void flash_attn_mma_stages(torch::Tensor Q, torch::Tensor K, 
                           torch::Tensor V, torch::Tensor O, 
                           int stages) {
  CHECK_TORCH_TENSOR_DTYPE(Q, torch::kHalf) // Q   [B,H,N,D]
  CHECK_TORCH_TENSOR_DTYPE(K, torch::kHalf) // K^T [B,H,D,N], transposed.
  CHECK_TORCH_TENSOR_DTYPE(V, torch::kHalf) // V   [B,H,N,D]
  CHECK_TORCH_TENSOR_DTYPE(O, torch::kHalf) // O   [B,H,N,D]
  const int d = Q.size(3); // B, H, N, d

  if (stages == 2) {
    switch (d)
    {
    case 64:
      launch_flash_attn_mma<64,  2>(Q, K, V, O);
      break;
    case 96:
      launch_flash_attn_mma<96,  2>(Q, K, V, O);
      break;
    case 128:
      launch_flash_attn_mma<128, 2>(Q, K, V, O);
      break;
    default:
      throw std::runtime_error("headdim not support!");
      break;
    }
  } else {
    switch (d)
    {
    case 64:
      launch_flash_attn_mma<64,  1>(Q, K, V, O);
      break;
    case 96:
      launch_flash_attn_mma<96,  1>(Q, K, V, O);
      break;
    case 128:
      launch_flash_attn_mma<128, 1>(Q, K, V, O);
      break;
    default:
      throw std::runtime_error("headdim not support!");
      break;
    }
  }
}

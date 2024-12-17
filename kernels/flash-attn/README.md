## ⚡️⚡️FlashAttention-2 MMA: Write FlashAttention using Tensor Cores with pure MMA PTX 

![flash-attn-mma](https://github.com/user-attachments/assets/6f66796d-44d5-4ec1-b224-af997bd152b2)

|Tensor Cores|Loop over Seqlen/HeadDim |Tile Block (Br, Bc)|MMA (m16n8k16)|
|:---:|:---:|:---:|:---:|
|✔️|✔️|✔️|✔️|
|Pack LDST (pack 128 bits)|SMEM Padding|Copy Async (cp.async.cg/ca)|Tile MMA (More Threads)
|✔️|✔️|✔️|✔️|
|Tile Warp (More Values)|Multi Stages (1/2)|Collective Store (Warp Shuffle & Reg Reuse)|**Split KV/Q**|
|✔️|✔️|✔️|✔️|
|Shared KV SMEM|Fully Shared QKV SMEM|Prefetch Q s2r|SMEM Swizzle|
|✔️|✔️|✔️|?|

This repository's implementation of FlashAttention is intended solely for learning CUDA programming. For optimal performance, please use the official [flash-attention](https://github.com/Dao-AILab/flash-attention). Currently, for small-scale attention (SeqLen <= 8192), the flash-attention-mma implemented in this repository matches the performance of the official FA. However, for large-scale attention computations, there remains a significant performance gap. Performance optimizations are ongoing; stay tuned for updates.

## 📖 Contents

- [📖 FlashAttetion MMA Kernels](#mma)
  - [📚 Split KV](#mma-split-kv)
  - [📚 Split Q ](#mma-split-q)
  - [📚 Shared KV SMEM](#mma-share-kv)
  - [📚 Fully Shared QKV SMEM](#mma-share-qkv)
- [📖 Prerequisites](#prerequisites)
- [📖 Installation](#install)
- [📖 Performance](#perf)
- [📖 Python Testing](#test)
  
## 📖 FlashAttetion MMA Kernels
<div id="mma"></div>  

The `Split KV` and `Split Q` implementations have been carried out in [flash-attention-mma⚡️⚡️](.) for performance comparison. The `Split KV` method, which involves splitting all QKV across MMA (Warps) using a naive matmul (MMA) and Warp tiling policy, is slower compared to the `Split Q` policy, which splitting Q across MMA(Warps) and keep access KV for all MMA(Warps).
<!--
![flash-attn](https://github.com/user-attachments/assets/11490fbc-2a4a-4630-abe8-91a9d1251cba)
-->
- 📚 Split KV (Basic, FlashAttention-1)
<div id="mma-split-kv"></div>  

```C++
// Split QKV across MMA(Warps) using naive matmul MMA&Warp tiling policy.
// case: The layout of 8 MMA(2x4)  [after] kWarpTileSeqLenQxkWarpTileSeqLenK(2x2) -> 32x2,32x2=64x64: 
// |  [64,64]  |    warp_KV 0    |    warp_KV 1    |    warp_KV 2    |    warp_KV 3    |
// | warp_QP 0 |-- MMA 0,MMA 0 --|-- MMA 2,MMA 2 --|-- MMA 4,MMA 4 --|-- MMA 6,MMA 6 --|
// | warp_QP 0 |-- MMA 0,MMA 0 --|-- MMA 2,MMA 2 --|-- MMA 4,MMA 4 --|-- MMA 6,MMA 6 --|
// | warp_QP 1 |-- MMA 1,MMA 1 --|-- MMA 3,MMA 2 --|-- MMA 5,MMA 5 --|-- MMA 7,MMA 7 --|
// | warp_QP 1 |-- MMA 1,MMA 1 --|-- MMA 3,MMA 2 --|-- MMA 5,MMA 5 --|-- MMA 7,MMA 7 --|
__global__ void 
flash_attn_mma_stages_split_kv_kernel(half* Q, // [B, H, N, D]
                                      half* K, // [B, H, D, N] K^T transposed 
                                      half* V, // [B, H, N, D] 
                                      half* O, // [B, H, N, D] 
                                      int QKV_seqlen);
```

- 📚 Split Q (Faster, FlashAttention-2)
<div id="mma-split-q"></div>  

```C++
// Split Q across MMA(Warps) and keep access KV for all MMA(Warps),
// in order to reduce the comm between warps via smem and warp shuffle.
// case: MMA = m16n8k16, Br=16x4=64, Bc=8x8=64, layout: 4 warps
// |   64x64   |      warp_KV 0       |
// | warp_QP 0 | MMA 0 ... MMA 0 (x8) |
// | warp_QP 1 | MMA 1 ... MMA 1 (x8) |
// | warp_QP 2 | MMA 2 ... MMA 2 (x8) |
// | warp_QP 3 | MMA 3 ... MMA 3 (x8) |
__global__ void
flash_attn_mma_stages_split_q_kernel(half* Q, // [B, H, N, D]
                                     half* K, // [B, H, D, N] K^T transposed 
                                     half* V, // [B, H, N, D] 
                                     half* O, // [B, H, N, D] 
                                     int QKV_seqlen);
```

- 📚 Split Q + Shared KV SMEM (Faster+)
<div id="mma-share-kv"></div>  

```C++
// K, V shared the same shared memory, improve block occupancy.
__global__ void 
flash_attn_mma_stages_split_q_shared_kv_kernel(half* Q, 
                                               half* K, 
                                               half* V, 
                                               half* O, 
                                               int QKV_seqlen);
```
- 📚 Split Q + Fully Shared QKV SMEM (Faster++)

<div id="mma-share-qkv"></div>  

```C++
// Q, K, V fully shared the same shared memory, improve block occupancy.
__global__ void 
flash_attn_mma_stages_split_q_shared_qkv_kernel(half* Q, 
                                                half* K, 
                                                half* V, 
                                                half* O, 
                                                int QKV_seqlen);
```

## 📖 Prerequisites
<div id="prerequisites"></div>  

- flash-attention >= 2.6
- PyTorch >= 2.0, CUDA >= 12.0
- Recommended: PyTorch 2.5.1, CUDA 12.5

## 📖 Installation  
<div id="install"></div>    

```bash
pip install flash-attn --no-build-isolation # need offical flash-attention for comparison
```

## 📖 Performance
<div id="perf"></div>  

Currently, for small-scale attention (SeqLen <= 8192), the flash-attention-mma implemented in this repository matches the performance of the official FA version. However, for large-scale attention computations, there remains a significant performance gap. Performance optimizations are ongoing; stay tuned for updates.

## 📖 Python Testing  
<div id="test"></div>  

```bash
cd kernels/flash-attn
# Volta, Ampere, Ada, Hopper, ...
python3 -m pip install flash-attn --no-build-isolation
export TORCH_CUDA_ARCH_LIST=Ada # for Ada only
export TORCH_CUDA_ARCH_LIST=Ampere # for Ampere only 
python3 flash_attn_mma.py --D 64 # test all default settings for D=64
```

- B=2, H=2, N=4096, D=64
  
```bash
python3 flash_attn_mma.py --B 2 --H 2 --D 64 --N 4096 # NVIDIA L20
------------------------------------------------------------------------------------------------------------------------
                    B: batch_size, H: n_head, N: seq_len, D: head_dim, seed: 3268, Warmup: 2, Iters: 10
------------------------------------------------------------------------------------------------------------------------
                              B=2, H=2, N=4096, D=64, Warmup: 2, Iters: 10
     mma(split-kv+stage1): ['-0.04187012 ', '0.05764771  ', '-0.00485992 '], time:0.323963ms, TFLOPS:54.06
     mma(split-kv+stage2): ['-0.04187012 ', '0.05764771  ', '-0.00485992 '], time:0.284553ms, TFLOPS:61.55
      mma(split-q+stage1): ['-0.04187012 ', '0.05764771  ', '-0.00485992 '], time:0.225067ms, TFLOPS:77.82
      mma(split-q+stage2): ['-0.04187012 ', '0.05764771  ', '-0.00485992 '], time:0.256133ms, TFLOPS:68.38
                  (flash): ['-0.04190063 ', '0.05761719  ', '-0.0049057  '], time:0.244427ms, TFLOPS:71.65
------------------------------------------------------------------------------------------------------------------------
```


- B=2, H=2, N=8192, D=64
```bash
python3 flash_attn_mma.py --B 2 --H 2 --D 64 --N 8192 # NVIDIA L20
------------------------------------------------------------------------------------------------------------------------
                    B: batch_size, H: n_head, N: seq_len, D: head_dim, seed: 2981, Warmup: 2, Iters: 10
------------------------------------------------------------------------------------------------------------------------
                              B=2, H=2, N=8192, D=64, Warmup: 2, Iters: 10
     mma(split-kv+stage1): ['-0.02342224 ', '0.0209198   ', '0.02729797  '], time:1.094031ms, TFLOPS:64.04
     mma(split-kv+stage2): ['-0.02342224 ', '0.0209198   ', '0.02729797  '], time:1.036191ms, TFLOPS:67.61
      mma(split-q+stage1): ['-0.02342224 ', '0.0209198   ', '0.02729797  '], time:0.909352ms, TFLOPS:77.04
      mma(split-q+stage2): ['-0.02342224 ', '0.0209198   ', '0.02729797  '], time:0.943947ms, TFLOPS:74.22
                  (flash): ['-0.02340698 ', '0.0209198   ', '0.02728271  '], time:0.703907ms, TFLOPS:99.53
------------------------------------------------------------------------------------------------------------------------
```

- B=1, H=8, N=8192, D=64
```bash
python3 flash_attn_mma.py --B 1 --H 8 --D 64 --N 8192 # NVIDIA L20
------------------------------------------------------------------------------------------------------------------------
                    B: batch_size, H: n_head, N: seq_len, D: head_dim, seed: 3279, Warmup: 2, Iters: 10
------------------------------------------------------------------------------------------------------------------------
                              B=1, H=8, N=8192, D=64, Warmup: 2, Iters: 10
     mma(split-kv+stage1): ['0.0181427   ', '-0.01678467 ', '-0.02586365 '], time:2.160978ms, TFLOPS:64.84
     mma(split-kv+stage2): ['0.0181427   ', '-0.01678467 ', '-0.02586365 '], time:2.053237ms, TFLOPS:68.24
      mma(split-q+stage1): ['0.0181427   ', '-0.01678467 ', '-0.02586365 '], time:1.690006ms, TFLOPS:82.91
      mma(split-q+stage2): ['0.0181427   ', '-0.01678467 ', '-0.02586365 '], time:1.858854ms, TFLOPS:75.38
                  (flash): ['0.01815796  ', '-0.01675415 ', '-0.02584839 '], time:1.366282ms, TFLOPS:102.55
------------------------------------------------------------------------------------------------------------------------
```

- B=1, H=48, N=8192, D=64  
```bash
python3 flash_attn_mma.py --B 1 --H 48 --D 64 --N 8192  # NVIDIA L20
------------------------------------------------------------------------------------------------------------------------
                    B: batch_size, H: n_head, N: seq_len, D: head_dim, seed: 2491, Warmup: 2, Iters: 10
------------------------------------------------------------------------------------------------------------------------
                              B=1, H=48, N=8192, D=64, Warmup: 2, Iters: 10
     mma(split-kv+stage1): ['-0.00775146 ', '0.01187897  ', '0.02755737  '], time:12.174153ms, TFLOPS:69.06
     mma(split-kv+stage2): ['-0.00775146 ', '0.01187897  ', '0.02755737  '], time:11.572266ms, TFLOPS:72.65
      mma(split-q+stage1): ['-0.00775146 ', '0.01187897  ', '0.02755737  '], time:9.648752ms,  TFLOPS:87.13
      mma(split-q+stage2): ['-0.00775146 ', '0.01187897  ', '0.02755737  '], time:10.584569ms, TFLOPS:79.43
                  (flash): ['-0.00776672 ', '0.0118866   ', '0.02757263  '], time:7.596278ms,  TFLOPS:110.67
------------------------------------------------------------------------------------------------------------------------
```

<div align='center'>
  <img src='https://github.com/user-attachments/assets/b2578723-b7a7-4d8f-bcd1-5008947b808a' >
</div> 

<div align='center'>
  <img src=https://cdn.rawgit.com/sindresorhus/awesome/d7305f38d29fed78fa85652e3a63e154dd8e8829/media/badge.svg >
  <img src=https://img.shields.io/badge/Language-CUDA-brightgreen.svg >
  <img src=https://img.shields.io/github/watchers/DefTruth/cuda-learn-note?color=9cc >
  <img src=https://img.shields.io/github/forks/DefTruth/cuda-learn-note.svg?style=social >
  <img src=https://img.shields.io/github/stars/DefTruth/cuda-learn-note.svg?style=social >
  <img src=https://img.shields.io/badge/Release-v2.6-brightgreen.svg >
  <img src=https://img.shields.io/badge/License-GPLv3.0-turquoise.svg >
 </div>   

<div id="contents"></div>  

📚 **Modern CUDA Learn Notes with PyTorch** for Beginners: It includes **Tensor/CUDA Cores, TF32/F16/BF16/F8**, [📖150+ CUDA Kernels🔥🔥(Easy -> Hard++)](#cuda-kernel) with PyTorch bindings, [📖100+ LLM/VLM/CV/CUDA/CuTe🔥](#my-blogs-part-1) blogs, [📖toy-hgemm⚡️⚡️](./kernels/hgemm) which can achieve `98%~100%` performance of **cuBLAS**, and [📖flash-attention-mma⚡️⚡️](./kernels/flash-attn) using Tensor Cores with pure MMA PTX. Welcome to 🌟👆🏻star this repo to support me, many thanks ~ 🎉🎉

<div id="hgemm-sgemm"></div>  

<div align='center'>
  <img src='https://github.com/user-attachments/assets/71927ac9-72b3-4ce9-b0e2-788b5885bc99' height="170px" width="270px">
  <img src='https://github.com/user-attachments/assets/05ef4f5e-d999-48ea-b58e-782cffb24e85' height="170px" width="270px">
  <img src='https://github.com/user-attachments/assets/9472e970-c083-4b31-9252-3eeecc761078' height="170px" width="270px">
</div> 

Currently, on NVIDIA L20, RTX 4090 and RTX 3080 Laptop, compared with cuBLAS's default Tensor Cores algorithm, the `HGEMM (WMMA/MMA/CuTe)` in this repo (`blue`🔵) can achieve `98%~100%` of its (`orange`🟠) performance. Please check [toy-hgemm library⚡️⚡️](./kernels/hgemm) or [hgemm-tensorcores-mma⚡️⚡️](https://github.com/DefTruth/hgemm-tensorcores-mma) repo for more details.

![toy-hgemm-library](https://github.com/user-attachments/assets/962bda14-b494-4423-b8eb-775da9f5503d)

|CUDA Cores|Sliced K (Loop over K)|Tile Block (BMxBK)|Tile Thread (t 8x8)|
|:---:|:---:|:---:|:---:|
|✔️|✔️|✔️|✔️|
|WMMA (m16n16k16)|MMA (m16n8k16)|Pack LDST (128 bits)|SMEM Padding|
|✔️|✔️|✔️|✔️|
|Copy Async|Tile MMA (More Threads)|Tile Warp (More Values)|Multi Stages (2/3/4)|  
|✔️|✔️|✔️|✔️|
|Reg Double Buffers|Block Swizzle|Warp Swizzle|SMEM Swizzle (CuTe)|
|✔️|✔️|✔️|✔️|
|Collective Store (Warp Shfl)|Row Major (NN)|Col Major (TN)| SGEMM FP32/TF32|
|✔️|✔️|✔️|✔️|


I have also implemented **FlashAttention-2** using pure MMA PTX instructions, which supports features such as Multi-Stages, Tile MMA, Tile Warp, Shared KV SMEM, **Fully Shared QKV SMEM**, **Prefetch Q s2r**, Collective Store, etc. Please refer to [flash-attention-mma⚡️⚡️](./kernels/flash-attn) for more details.

![flash-attn-mma](https://github.com/user-attachments/assets/6f66796d-44d5-4ec1-b224-af997bd152b2)

|Tensor Cores|Loop over Seqlen/Headdim |Tile Block (Br, Bc)|MMA (m16n8k16)|
|:---:|:---:|:---:|:---:|
|✔️|✔️|✔️|✔️|
|Pack LDST (128 bits)|SMEM Padding|Copy Async|Tile MMA (More Threads)|
|✔️|✔️|✔️|✔️|
|Tile Warp (More Values)|Multi Stages (1/2)|Collective Store (Shfl)|**Split KV/Q**|
|✔️|✔️|✔️|✔️|
|**Shared QKV/KV** SMEM|**Prefetch Q** s2r|**Prefetch K/V** g2s|SMEM/Block Swizzle|
|✔️|✔️|✔️|?|

Currently, for small-scale attention `(B<=4, H <=48, SeqLen <= 8192)` it can run faster than FA2/SDPA on some Devices. For example, on NVIDIA RTX 3080 Laptop, [📚 Split Q + Fully Shared QKV SMEM](#mma-share-qkv) can achieve **55 TFLOPS (D=64)** that almost **~1.5x** 🎉 faster than FA2. On NVIDIA L20, [📚 Split Q + QK Fine-grained Tiling](#mma-tiling-qk) can achieve **81 TFLOPS (D=512)** that almost **~1.4x** 🎉 faster than SDPA (EFFICIENT ATTENTION). However, for large-scale attention, there remains a performance gap. Stay tuned for updates ~ 

- Example: B=1, H=8, N=8192, `D=64` (NVIDIA RTX 3080 Laptop), Faster than FA2~🎉🎉
```bash
python3 flash_attn_mma.py --B 1 --H 8 --D 64 --N 8192 --iters 10 --torch # NVIDIA RTX 3080 Laptop
-------------------------------------------B=1, H=8, N=8192, D=64, Warmup: 1, Iters: 10-------------------------------------------
                  torch(unfused): ['-0.00514603 ', '0.05783081  ', '-0.00026727 '], time:20.999861ms, TFLOPS:6.67 (+0.00%)
            mma(split-kv+stage1): ['-0.00511169 ', '0.05795288  ', '-0.00029612 '], time:5.120730ms, TFLOPS:27.36 (+310.10%)
            mma(split-kv+stage2): ['-0.00511169 ', '0.05795288  ', '-0.00029612 '], time:5.004287ms, TFLOPS:28.00 (+2.33%)
             mma(split-q+stage1): ['-0.00511169 ', '0.05795288  ', '-0.00029612 '], time:3.462291ms, TFLOPS:40.47 (+44.54%)
             mma(split-q+stage2): ['-0.00511169 ', '0.05795288  ', '-0.00029612 '], time:3.658915ms, TFLOPS:38.30
   mma(split-q+share-qkv+stage1): ['-0.00511169 ', '0.05795288  ', '-0.00029612 '], time:2.551699ms, TFLOPS:54.91 (+35.69%)
   mma(split-q+share-qkv+stage2): ['-0.00511169 ', '0.05795288  ', '-0.00029612 '], time:2.532172ms, TFLOPS:55.34 (+0.77%)
    mma(split-q+share-kv+stage1): ['-0.00511169 ', '0.05795288  ', '-0.00029612 '], time:2.776575ms, TFLOPS:50.46
    mma(split-q+share-kv+stage2): ['-0.00511169 ', '0.05795288  ', '-0.00029612 '], time:2.596927ms, TFLOPS:53.96
                         (flash): ['-0.00516129 ', '0.05783081  ', '-0.00027728 '], time:3.776550ms, TFLOPS:37.10
----------------------------------------------------------------------------------------------------------------------------------
```

- Example: B=1, H=48, N=8192, `D=512` (RTX 3080), FA2 not supported, `QK Tiling` Faster than SDPA~🎉🎉
```bash
python3 flash_attn_mma.py --B 1 --H 8 --N 8192 --iters 10 --show-all --sdpa --D 512 # NVIDIA RTX 3080 Laptop, Faster than SDPA
------------------------------------------B=1, H=8, N=8192, D=512, Warmup: 1, Iters: 10-------------------------------------------
   mma(split-q+tiling-qk+stage1): ['-0.00433731 ', '0.02165222  ', '-0.01544189 '], time:48.775554ms, TFLOPS:22.60 (+0.00%)
   mma(split-q+tiling-qk+stage2): ['-0.00433731 ', '0.02165222  ', '-0.01544189 '], time:47.503424ms, TFLOPS:23.20 (+2.68%)
                          (sdpa): ['-0.00438309 ', '0.02174377  ', '-0.01551056 '], time:66.486573ms, TFLOPS:16.58
----------------------------------------------------------------------------------------------------------------------------------
```

- Example: B=1, H=48, N=8192, `D=512` (NVIDIA L20), FA2 not supported, `QK Tiling` Faster than SDPA~🎉🎉
```bash
python3 flash_attn_mma.py --B 1 --H 48 --D 512 --N 16384 --show-all --check --iters 10 --sdpa
-----------------------------------------B=1, H=48, N=16384, D=512, Warmup: 1, Iters: 10------------------------------------------
   mma(split-q+tiling-qk+stage1): ['0.0079422   ', '-0.02334595 ', '0.00881958  '], time:387.384224ms, TFLOPS:68.28 (+0.00%)
   mma(split-q+tiling-qk+stage2): ['0.0079422   ', '-0.02334595 ', '0.00881958  '], time:325.593209ms, TFLOPS:81.24 (+18.98%)
                          (sdpa): ['0.00790405  ', '-0.02330017 ', '0.00875854  '], time:452.067018ms, TFLOPS:58.51
----------------------------------------------------------------------------------------------------------------------------------
```

The `Split KV` and `Split Q` implementations have been carried out in [flash-attention-mma⚡️⚡️](./kernels/flash-attn) for performance comparison. The `Split KV` method, which involves splitting all QKV across MMA (Warps), is slower than `Split Q` policy, which splitting Q across MMA(Warps) and keep access KV for all MMA(Warps). 

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
__global__ void // Q, K, V, O -> [B, H, N, D]
flash_attn_mma_stages_split_kv_kernel(half* Q, half* K, half* V, half* O, ...);
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
__global__ void // Q, K, V, O -> [B, H, N, D]
flash_attn_mma_stages_split_q_kernel(half* Q, half* K, half* V, half* O, ...);
```

- 📚 Split Q + Shared KV SMEM (**1/2 SRAM** vs FA2)
<div id="mma-share-kv"></div>  

```C++
// K, V shared the same shared memory, improve block occupancy.
__global__ void // Q, K, V, O -> [B, H, N, D]
flash_attn_mma_stages_split_q_shared_kv_kernel(half* Q, half* K, half* V, half* O, ...);
```
- 📚 Split Q + Fully Shared QKV SMEM (**1/4 SRAM** vs FA2)

<div id="mma-share-qkv"></div>  

```C++
// Q, K, V fully shared the same shared memory and prefetch Q s2r, improve block occupancy
// and reduce Q SMEM IO-Access.
__global__ void // Q, K, V, O -> [B, H, N, D]
flash_attn_mma_stages_split_q_shared_qkv_kernel(half* Q, half* K, half* V, half* O, ...);
```
- 📚 Split Q + QK Fine-grained Tiling (**O(16xd) SRAM** vs FA2 **O(4xBrxd) SRAM**, `Headdim -> 1024`)

<div id="mma-tiling-qk"></div>  

```C++
// Fine-grained tiling at the MMA level for Q and K results in a constant SRAM usage of
// 64 * kMmaAtomK for Q and K. For V, the SRAM complexity is O(kMmaAtomK * d), leading to
// an overall SRAM complexity of O(kMmaAtomK * d). Consequently, this approach allows us to
// extend D (head dimension) up to 1024. Stay tuned for updates ~
__global__ void // Q, K, V, O -> [B, H, N, D]
flash_attn_mma_stages_split_q_tiling_qk_kernel(half* Q, half* K, half* V, half* O, ...);
```
## ©️Citations🎉🎉

```BibTeX
@misc{CUDA-Learn-Notes@2024,
  title={CUDA-Learn-Notes: A Modern CUDA Learn Notes with PyTorch for Beginners},
  url={https://github.com/DefTruth/CUDA-Learn-Notes},
  note={Open-source software available at https://github.com/DefTruth/CUDA-Learn-Notes},
  author={DefTruth etc},
  year={2024}
}
```

## 📖 150+ CUDA Kernels 🔥🔥 (Easy -> Hard++) ([©️back👆🏻](#contents))  

<div id="cuda-kernel"></div>    

The kernels listed here will guide you through a step-by-step progression, ranging from easy to very challenging topics. The **workflow** for each topic will be as follows: custom **CUDA kernel** implementation -> PyTorch **Python bindings** -> Run tests. 👉TIPS: `*` = Tensor Cores (WMMA, MMA, CuTe), otherwise, CUDA Cores; `/` = not supported; `✔️` = supported; `❔` = TODO. Contents are listed as follows:  

- [📚 Easy ⭐️](#cuda-kernel-easy-medium)
- [📚 Medium ⭐️⭐️](#cuda-kernel-easy-medium)
- [📚 Hard ⭐️⭐️⭐️](#cuda-kernel-hard)
- [📚 Hard+ ⭐️⭐️⭐️⭐️](#cuda-kernel-hard-plus)
- [📚 Hard++ ⭐⭐⭐️⭐️⭐️](#cuda-kernel-hard-plus)

[📚 Easy](#cuda-kernel-easy-medium) and [📚 Medium](#cuda-kernel-easy-medium) sections cover operations such as `element-wise, mat_trans, warp/block reduce, nms, relu, gelu, swish, layer-norm, rms-norm, online-softmax, dot-prod, embedding` and basic usage for `FP32`, `FP16`, `BF16` and `FP8` . [📚 Hard](#cuda-kernel-hard), [📚 Hard+](#cuda-kernel-hard-plus) and [📚 Hard++](#cuda-kernel-hard-plus) sections delve deeper into advanced topics, primarily focusing on operations like `sgemv, sgemm, hgemv, hgemm and flash-attention`. These sections also provide numerous kernels implemented using Tensor Cores with pure MMA PTX.

### 📚 Easy ⭐️ & Medium ⭐️⭐️  ([©️back👆🏻](#cuda-kernel))  
<div id="cuda-kernel-easy-medium"></div>  

|📖 CUDA Kernel| 📖 Elem DType| 📖 Acc DType| 📖 Docs | 📖 Level |
|:---|:---|:---|:---|:---|  
| ✔️ [nsys/ncu(timeline/ptx/sass)](./kernels/nvidia-nsight/)|/|/|[link](./kernels/nvidia-nsight/)|⭐️| 
| ✔️ [elementwise_f32](./kernels/elementwise/elementwise.cu)|f32|/|[link](./kernels/elementwise/)|⭐️|
| ✔️ [elementwise_f32x4](./kernels/elementwise/elementwise.cu)|f32|/|[link](./kernels/elementwise/)|⭐️|
| ✔️ [elementwise_f16](./kernels/elementwise/elementwise.cu)|f16|/|[link](./kernels/elementwise/)|⭐️|
| ✔️ [elementwise_f16x2](./kernels/elementwise/elementwise.cu)|f16|/|[link](./kernels/elementwise/)|⭐️|
| ✔️ [elementwise_f16x8](./kernels/elementwise/elementwise.cu)|f16|/|[link](./kernels/elementwise/)|⭐️|
| ✔️ [elementwise_f16x8_pack](./kernels/elementwise/elementwise.cu)|f16|/|[link](./kernels/elementwise/)|⭐️⭐️|
| ✔️ [histogram_i32](./kernels/histogram/histogram.cu)|i32|/|[link](./kernels/histogram/)|⭐️|
| ✔️ [histogram_i32x4](./kernels/histogram/histogram.cu)|i32|/|[link](./kernels/histogram/)|⭐️|  
| ✔️ [sigmoid_f32](./kernels/sigmoid/sigmoid.cu)|f32|/|[link](./kernels/sigmoid/)|⭐️|  
| ✔️ [sigmoid_f32x4](./kernels/sigmoid/sigmoid.cu)|f32|/|[link](./kernels/sigmoid/)|⭐️|  
| ✔️ [sigmoid_f16](./kernels/sigmoid/sigmoid.cu)|16|/|[link](./kernels/sigmoid/)|⭐️|  
| ✔️ [sigmoid_f16x2](./kernels/sigmoid/sigmoid.cu)|f16|/|[link](./kernels/sigmoid/)|⭐️|  
| ✔️ [sigmoid_f16x8](./kernels/sigmoid/sigmoid.cu)|f16|/|[link](./kernels/sigmoid/)|⭐️|  
| ✔️ [sigmoid_f16x8_pack](./kernels/sigmoid/sigmoid.cu)|f16|/|[link](./kernels/sigmoid/)|⭐️⭐️|  
| ✔️ [relu_f32](./kernels/relu/relu.cu)|f32|/|[link](./kernels/relu/)|⭐️|  
| ✔️ [relu_f32x4](./kernels/relu/relu.cu)|f32|/|[link](./kernels/relu/)|⭐️|  
| ✔️ [relu_f16](./kernels/relu/relu.cu)|f16|/|[link](./kernels/relu/)|⭐️|  
| ✔️ [relu_f16x2](./kernels/relu/relu.cu)|f16|/|[link](./kernels/relu/)|⭐️|  
| ✔️ [relu_f16x8](./kernels/relu/relu.cu)|f16|/|[link](./kernels/relu/)|⭐️|  
| ✔️ [relu_f16x8_pack](./kernels/relu/relu.cu)|f16|/|[link](./kernels/relu/)|⭐️⭐️|  
| ✔️ [gelu_f32](./kernels/gelu/gelu.cu)|f32|/|[link](./kernels/gelu/)|⭐️|  
| ✔️ [gelu_f32x4](./kernels/gelu/gelu.cu)|f32|/|[link](./kernels/gelu/)|⭐️|  
| ✔️ [gelu_f16](./kernels/gelu/gelu.cu)|f16|/|[link](./kernels/gelu/)|⭐️|  
| ✔️ [gelu_f16x2](./kernels/gelu/gelu.cu)|f16|/|[link](./kernels/gelu/)|⭐️|  
| ✔️ [gelu_f16x8](./kernels/gelu/gelu.cu)|f16|/|[link](./kernels/gelu/)|⭐️|  
| ✔️ [gelu_f16x8_pack](./kernels/gelu/gelu.cu)|f16|/|[link](./kernels/gelu/)|⭐️⭐️|  
| ✔️ [swish_f32](./kernels/swish/swish.cu)|f32|/|[link](./kernels/swish/)|⭐️|  
| ✔️ [swish_f32x4](./kernels/swish/swish.cu)|f32|/|[link](./kernels/swish/)|⭐️|  
| ✔️ [swish_f16](./kernels/swish/swish.cu)|f16|/|[link](./kernels/swish/)|⭐️|  
| ✔️ [swish_f16x2](./kernels/swish/swish.cu)|f16|/|[link](./kernels/swish/)|⭐️|  
| ✔️ [swish_f16x8](./kernels/swish/swish.cu)|f16|/|[link](./kernels/swish/)|⭐️|  
| ✔️ [swish_f16x8_pack](./kernels/swish/swish.cu)|f16|/|[link](./kernels/swish/)|⭐️⭐️|  
| ✔️ [embedding_f32](./kernels/embedding/embedding.cu)|f32|/|[link](./kernels/embedding/)|⭐️|  
| ✔️ [embedding_f32x4](./kernels/embedding/embedding.cu)|f32|/|[link](./kernels/embedding/)|⭐️|  
| ✔️ [embedding_f32x4_pack](./kernels/embedding/embedding.cu)|f32|/|[link](./kernels/embedding/)|⭐️|  
| ✔️ [embedding_f16](./kernels/embedding/embedding.cu)|f16|/|[link](./kernels/embedding/)|⭐️|  
| ✔️ [embedding_f16x2](./kernels/embedding/embedding.cu)|f16|/|[link](./kernels/embedding/)|⭐️|  
| ✔️ [embedding_f16x8](./kernels/embedding/embedding.cu)|f16|/|[link](./kernels/embedding/)|⭐️|  
| ✔️ [embedding_f16x8_pack](./kernels/embedding/embedding.cu)|f16|/|[link](./kernels/embedding/)|⭐️⭐️| 
| ✔️ [mat_trans_f32_col2row{2d}](./kernels/mat-transpose/mat_transpose.cu)|f32|/|[link](./kernels/mat-transpose/)|⭐️|  
| ✔️ [mat_trans_f32_row2col{2d}](./kernels/mat-transpose/mat_transpose.cu)|f32|/|[link](./kernels/mat-transpose/)|⭐️|  
| ✔️ [mat_trans_f32_diagonal2d](./kernels/mat-transpose/mat_transpose.cu)|f32|/|[link](./kernels/mat-transpose/)|⭐️⭐️|  
| ✔️ [mat_trans_f32x4_col2row{2d}](./kernels/mat-transpose/mat_transpose.cu)|f32|/|[link](./kernels/mat-transpose/)|⭐️⭐️|  
| ✔️ [mat_trans_f32x4_row2col{2d}](./kernels/mat-transpose/mat_transpose.cu)|f32|/|[link](./kernels/mat-transpose/)|⭐️⭐️|  
| ✔️ [warp_reduce_[all]](./kernels/reduce/block_all_reduce.cu)|all|all|[link](./kernels/reduce/)|⭐️⭐️|  
| ✔️ [reduce_f32_f32](./kernels/reduce/block_all_reduce.cu)|f32|f32|[link](./kernels/reduce/)|⭐️⭐️|  
| ✔️ [reduce_f32x4_f32](./kernels/reduce/block_all_reduce.cu)|f32|f32|[link](./kernels/reduce/)|⭐️⭐️|  
| ✔️ [reduce_f16_f16](./kernels/reduce/block_all_reduce.cu)|f16|f16|[link](./kernels/reduce/)|⭐️⭐️|  
| ✔️ [reduce_f16_f32](./kernels/reduce/block_all_reduce.cu)|f16|f32|[link](./kernels/reduce/)|⭐️⭐️|  
| ✔️ [reduce_f16x2_f16](./kernels/reduce/block_all_reduce.cu)|f16|f16|[link](./kernels/reduce/)|⭐️⭐️|  
| ✔️ [reduce_f16x2_f32](./kernels/reduce/block_all_reduce.cu)|f16|f32|[link](./kernels/reduce/)|⭐️⭐️|  
| ✔️ [reduce_f16x8_pack_f16](./kernels/reduce/block_all_reduce.cu)|f16|f16|[link](./kernels/reduce/)|⭐️⭐️|  
| ✔️ [reduce_f16x8_pack_f32](./kernels/reduce/block_all_reduce.cu)|f16|f32|[link](./kernels/reduce/)|⭐️⭐️|  
| ✔️ [reduce_bf16_bf16](./kernels/reduce/block_all_reduce.cu)|bf16|bf16|[link](./kernels/reduce/)|⭐️⭐️|  
| ✔️ [reduce_bf16_f32](./kernels/reduce/block_all_reduce.cu)|bf16|f32|[link](./kernels/reduce/)|⭐️⭐️|  
| ✔️ [reduce_bf16x2_bf16](./kernels/reduce/block_all_reduce.cu)|bf16|bf16|[link](./kernels/reduce/)|⭐️⭐️|  
| ✔️ [reduce_bf16x2_f32](./kernels/reduce/block_all_reduce.cu)|bf16|f32|[link](./kernels/reduce/)|⭐️⭐️|  
| ✔️ [reduce_bf16x8_pack_bf16](./kernels/reduce/block_all_reduce.cu)|bf16|bf16|[link](./kernels/reduce/)|⭐️⭐️|  
| ✔️ [reduce_bf16x8_pack_f32](./kernels/reduce/block_all_reduce.cu)|bf16|f32|[link](./kernels/reduce/)|⭐️⭐️|  
| ✔️ [reduce_fp8_e4m3_f16](./kernels/reduce/block_all_reduce.cu)|fp8_e4m3|f16|[link](./kernels/reduce/)|⭐️⭐️|  
| ✔️ [reduce_fp8_e5m2_f16](./kernels/reduce/block_all_reduce.cu)|fp8_e5m2|f16|[link](./kernels/reduce/)|⭐️⭐️|  
| ✔️ [reduce_fp8_e4m3x16_pack_f16](./kernels/reduce/block_all_reduce.cu)|fp8_e4m3|f16|[link](./kernels/reduce/)|⭐️⭐️|  
| ✔️ [reduce_fp8_e5m2x16_pack_f16](./kernels/reduce/block_all_reduce.cu)|fp8_e5m2|f16|[link](./kernels/reduce/)|⭐️⭐️|  
| ✔️ [reduce_i8_i32](./kernels/reduce/block_all_reduce.cu)|i8|i32|[link](./kernels/reduce/)|⭐️⭐️|  
| ✔️ [reduce_i8x16_pack_i32](./kernels/reduce/block_all_reduce.cu)|i8|i32|[link](./kernels/reduce/)|⭐️⭐️|  
| ✔️ [dot_product_f32](./kernels/dot-product/dot_product.cu)|f32|f32|[link](./kernels/dot-product/)|⭐️⭐️|  
| ✔️ [dot_product_f32x4](./kernels/dot-product/dot_product.cu)|f32|f32|[link](./kernels/dot-product/)|⭐️⭐️|  
| ✔️ [dot_product_f16_f32](./kernels/dot-product/dot_product.cu)|f16|f32|[link](./kernels/dot-product/)|⭐️⭐️|  
| ✔️ [dot_product_f16x2_f32](./kernels/dot-product/dot_product.cu)|f16|f32|[link](./kernels/dot-product/)|⭐️⭐️|  
| ✔️ [dot_product_f16x8_pack_f32](./kernels/dot-product/dot_product.cu)|f16|f32|[link](./kernels/dot-product/)|⭐️⭐️|  
| ✔️ [softmax_f32(fence)](./kernels/softmax/softmax.cu)|f32|f32|[link](./kernels/softmax/)|⭐️⭐️|  
| ✔️ [softmax_f32x4(fence)](./kernels/softmax/softmax.cu)|f32|f32|[link](./kernels/softmax/)|⭐️⭐️|  
| ✔️ [softmax_f32](./kernels/softmax/softmax.cu)|f32|f32|[link](./kernels/softmax/)|⭐️⭐️|  
| ✔️ [softmax_f32x4](./kernels/softmax/softmax.cu)|f32|f32|[link](./kernels/softmax/)|⭐️⭐️|  
| ✔️ [safe_softmax_f32](./kernels/softmax/softmax.cu)|f32|f32|[link](./kernels/softmax/)|⭐️⭐️|  
| ✔️ [safe_softmax_f32x4](./kernels/softmax/softmax.cu)|f32|f32|[link](./kernels/softmax/)|⭐️⭐️|  
| ✔️ [safe_softmax_f16_f32](./kernels/softmax/softmax.cu)|f16|f32|[link](./kernels/softmax/)|⭐️⭐️|  
| ✔️ [safe_softmax_f16x2_f32](./kernels/softmax/softmax.cu)|f16|f32|[link](./kernels/softmax/)|⭐️⭐️|  
| ✔️ [safe_softmax_f16x8_pack_f32](./kernels/softmax/softmax.cu)|f16|f32|[link](./kernels/softmax/)|⭐️⭐️|  
| ✔️ [online_safe_softmax_f32](./kernels/softmax/softmax.cu)|f32|f32|[link](./kernels/softmax/)|⭐️⭐️|
| ✔️ [online_safe_softmax_f32x4_pack](./kernels/softmax/softmax.cu)|f32|f32|[link](./kernels/softmax/)|⭐️⭐️|
| ✔️ [rope_f32](./kernels/rope/rope.cu)|f32|f32|[link](./kernels/rope/)|⭐️⭐️|  
| ✔️ [rope_f32x4_pack](./kernels/rope/rope.cu)|f32|f32|[link](./kernels/rope/)|⭐️⭐️|  
| ✔️ [layer_norm_f32](./kernels/layer-norm/layer_norm.cu)|f32|f32|[link](./kernels/layer-norm/)|⭐️⭐️|  
| ✔️ [layer_norm_f32x4](./kernels/layer-norm/layer_norm.cu)|f32|f32|[link](./kernels/layer-norm/)|⭐️⭐️|  
| ✔️ [layer_norm_f16_f16](./kernels/layer-norm/layer_norm.cu)|f16|f16|[link](./kernels/layer-norm/)|⭐️⭐️|  
| ✔️ [layer_norm_f16x2_f16](./kernels/layer-norm/layer_norm.cu)|f16|f16|[link](./kernels/layer-norm/)|⭐️⭐️|  
| ✔️ [layer_norm_f16x8_f16](./kernels/layer-norm/layer_norm.cu)|f16|f16|[link](./kernels/layer-norm/)|⭐️⭐️|  
| ✔️ [layer_norm_f16x8_pack_f16](./kernels/layer-norm/layer_norm.cu)|f16|f16|[link](./kernels/layer-norm/)|⭐️⭐️|  
| ✔️ [layer_norm_f16x8_pack_f32](./kernels/layer-norm/layer_norm.cu)|f16|f32|[link](./kernels/layer-norm/)|⭐️⭐️|  
| ✔️ [layer_norm_f16_f32](./kernels/layer-norm/layer_norm.cu)|f16|f32|[link](./kernels/layer-norm/)|⭐️⭐️|  
| ✔️ [rms_norm_f32](./kernels/rms-norm/rms_norm.cu)|f32|f32|[link](./kernels/rms-norm/)|⭐️⭐️|  
| ✔️ [rms_norm_f32x4](./kernels/rms-norm/rms_norm.cu)|f32|f32|[link](./kernels/rms-norm/)|⭐️⭐️|  
| ✔️ [rms_norm_f16_f16](./kernels/rms-norm/rms_norm.cu)|f16|f16|[link](./kernels/rms-norm/)|⭐️⭐️|  
| ✔️ [rms_norm_f16x2_f16](./kernels/rms-norm/rms_norm.cu)|f16|f16|[link](./kernels/rms-norm/)|⭐️⭐️|  
| ✔️ [rms_norm_f16x8_f16](./kernels/rms-norm/rms_norm.cu)|f16|f16|[link](./kernels/rms-norm/)|⭐️⭐️|  
| ✔️ [rms_norm_f16x8_f32](./kernels/rms-norm/rms_norm.cu)|f16|f32|[link](./kernels/rms-norm/)|⭐️⭐️|  
| ✔️ [rms_norm_f16x8_pack_f16](./kernels/rms-norm/rms_norm.cu)|f16|f16|[link](./kernels/rms-norm/)|⭐️⭐️|  
| ✔️ [rms_norm_f16x8_pack_f32](./kernels/rms-norm/rms_norm.cu)|f16|f32|[link](./kernels/rms-norm/)|⭐️⭐️|  
| ✔️ [rms_norm_f16_f32](./kernels/rms-norm/rms_norm.cu)|f16|f32|[link](./kernels/rms-norm/)|⭐️⭐️| 
| ✔️ [nms_f32](./kernels/nms/nms.cu)|f32|/|[link](./kernels/nms)|⭐️⭐️|  
| ✔️ [notes v1(deprecated)](./kernels/notes-v1.cu)|f32|f32|/|⭐️|  

### 📚 Hard ⭐⭐⭐️ ([©️back👆🏻](#cuda-kernel))  

<div id="cuda-kernel-hard"></div>  

|📖 CUDA Kernel| 📖 Elem DType| 📖 Acc DType| 📖 Docs | 📖 Level |
|:---|:---|:---|:---|:---|    
| ✔️ [sgemv_k32_f32](./kernels/sgemv/sgemv.cu)|f32|f32|[link](./kernels/sgemv/)|⭐️⭐️⭐️|  
| ✔️ [sgemv_k128_f32x4](./kernels/sgemv/sgemv.cu)|f32|f32|[link](./kernels/sgemv/)|⭐️⭐️⭐️|  
| ✔️ [sgemv_k16_f32](./kernels/sgemv/sgemv.cu)|f32|f32|[link](./kernels/sgemv/)|⭐️⭐️⭐️|  
| ✔️ [hgemv_k32_f16](./kernels/hgemv/hgemv.cu)|f16|f16|[link](./kernels/hgemv/)|⭐️⭐️⭐️|  
| ✔️ [hgemv_k128_f16x4](./kernels/hgemv/hgemv.cu)|f16|f16|[link](./kernels/hgemv/)|⭐️⭐️⭐️|  
| ✔️ [hgemv_k16_f16](./kernels/hgemv/hgemv.cu)|f16|f16|[link](./kernels/hgemv/)|⭐️⭐️⭐️| 
| ✔️ [sgemm_naive_f32](./kernels/sgemm/sgemm.cu)|f32|f32|[link](./kernels/sgemm/)|⭐️⭐️|  
| ✔️ [sgemm_sliced_k_f32](./kernels/sgemm/sgemm.cu)|f32|f32|[link](./kernels/sgemm/)|⭐️⭐️⭐️|  
| ✔️ [sgemm_t_8x8_sliced_k_f32x4](./kernels/sgemm/sgemm.cu)|f32|f32|[link](./kernels/sgemm/)|⭐️⭐️⭐️|  
| ✔️ [sgemm_t_8x8_sliced_k...bcf](./kernels/sgemm/sgemm.cu)|f32|f32|[link](./kernels/sgemm/)|⭐️⭐️⭐️|  
| ✔️ [sgemm_t_8x8_sliced_k...dbuf](./kernels/sgemm/sgemm.cu)|f32|f32|[link](./kernels/sgemm/)|⭐️⭐️⭐️|  
| ✔️ [sgemm_t_8x8_sliced_k16...dbuf](./kernels/sgemm/sgemm_async.cu)|f32|f32|[link](./kernels/sgemm/)|⭐️⭐️⭐️|  
| ✔️ [sgemm_t_8x8_sliced_k16...async](./kernels/sgemm/sgemm_async.cu)|f32|f32|[link](./kernels/sgemm/)|⭐️⭐️⭐️|  
| ✔️ [sgemm_wmma_m16n16k8...stages*](./kernels/sgemm/sgemm_wmma_tf32_stage.cu)|tf32|f32|[link](./kernels/sgemm/)|⭐️⭐️⭐️|  
| ✔️ [sgemm_wmma_m16n16k8...swizzle*](./kernels/sgemm/sgemm_wmma_tf32_stage.cu)|tf32|f32|[link](./kernels/sgemm/)|⭐️⭐️⭐️|  
| ✔️ [hgemm_naive_f16](./kernels/hgemm/naive/hgemm.cu)|f16|f16|[link](./kernels/hgemm/)|⭐️⭐️|  
| ✔️ [hgemm_sliced_k_f16](./kernels/hgemm/naive/hgemm.cu)|f16|f16|[link](./kernels/hgemm/)|⭐️⭐️⭐️|  
| ✔️ [hgemm_t_8x8_sliced_k_f16x4](./kernels/hgemm/hgemm.cu)|f16|f16|[link](./kernels/hgemm/)|⭐️⭐️⭐️|  
| ✔️ [hgemm_t_8x8_sliced_k_f16x4_pack](./kernels/hgemm/naive/hgemm.cu)|f16|f16|[link](./kernels/hgemm/)|⭐️⭐️⭐️|  
| ✔️ [hgemm_t_8x8_sliced_k_f16x8_pack](./kernels/hgemm/naive/hgemm.cu)|f16|f16|[link](./kernels/hgemm/)|⭐️⭐️⭐️|  
| ✔️ [hgemm_t_8x8_sliced_k...dbuf](./kernels/hgemm/naive/hgemm.cu)|f16|f16|[link](./kernels/hgemm/)|⭐️⭐️⭐️|  
| ✔️ [hgemm_t_8/16x8...k16/32...dbuf](./kernels/hgemm/naive/hgemm_async.cu)|f16|f16|[link](./kernels/hgemm/)|⭐️⭐️⭐️|  
| ✔️ [hgemm_t_8/16x8...k16/32...async](./kernels/hgemm/naive/hgemm_async.cu)|f16|f16|[link](./kernels/hgemm/)|⭐️⭐️⭐️|  
| ✔️ [hgemm_wmma_m16n16k16...naive*](./kernels/hgemm/wmma/hgemm_wmma.cu)|f16|f16|[link](./kernels/hgemm/)|⭐️⭐️⭐️|  
| ✔️ [hgemm_wmma_m16n16k16...mma4x2*](./kernels/hgemm/wmma/hgemm_wmma.cu)|f16|f16|[link](./kernels/hgemm/)|⭐️⭐️⭐️|  
| ✔️ [hgemm_wmma_m16n16k16...mma4x4*](./kernels/hgemm/wmma/hgemm_wmma.cu)|f16|f16|[link](./kernels/hgemm/)|⭐️⭐️⭐️|  
| ✔️ [hgemm_wmma_m16n16k16...dbuf*](./kernels/hgemm/wmma/hgemm_wmma.cu)|f16|f16|[link](./kernels/hgemm/)|⭐️⭐️⭐️|  
| ✔️ [hgemm_wmma_m32n8k16....dbuf*](./kernels/hgemm/wmma/hgemm_wmma.cu)|f16|f16|[link](./kernels/hgemm/)|⭐️⭐️⭐️|  
| ✔️ [hgemm_wmma_m16n16k16...stages*](./kernels/hgemm/wmma/hgemm_wmma_stage.cu)|f16|f16|[link](./kernels/hgemm/)|⭐️⭐️⭐️|  
| ✔️ [hgemm_wmma_m16n16k16...swizzle*](./kernels/hgemm/wmma/hgemm_wmma_stage.cu)|f16|f16|[link](./kernels/hgemm/)|⭐️⭐️⭐️|  
| ✔️ [hgemm_mma_m16n8k16...naive*](./kernels/hgemm/mma/hgemm_mma.cu)|f16|f16|[link](./kernels/hgemm/)|⭐️⭐️⭐️|  
| ✔️ [hgemm_mma_m16n8k16...mma2x4*](./kernels/hgemm/mma/hgemm_mma.cu)|f16|f16|[link](./kernels/hgemm/)|⭐️⭐️⭐️|  
| ✔️ [hgemm_mma_m16n8k16...stages*](./kernels/hgemm/mma/hgemm_mma_stage.cu)|f16|f16|[link](./kernels/hgemm/)|⭐️⭐️⭐️|  
| ✔️ [hgemm_mma_m16n8k16...swizzle*](./kernels/hgemm/mma/hgemm_mma_stage.cu)|f16|f16|[link](./kernels/hgemm/)|⭐️⭐️⭐️|  
| ✔️ [hgemm_mma_stages{swizzle}...cute*](./kernels/hgemm/cutlass/hgemm_mma_stage_tn_cute.cu)|f16|f16|[link](./kernels/hgemm/)|⭐️⭐️⭐️|  
| ✔️ [hgemm_mma_cublas*](./kernels/hgemm/cublas/hgemm_cublas.cu)|f16|f16|[link](./kernels/hgemm/)|⭐️⭐️|   

### 📚 Hard+ ⭐️⭐️⭐️⭐️ & Hard++ ⭐️⭐️⭐️⭐️⭐️ ([©️back👆🏻](#cuda-kernel)) 

<div id="cuda-kernel-hard-plus"></div>  

|📖 CUDA Kernel| 📖 Elem DType| 📖 Acc DType| 📖 Docs | 📖 Level |
|:---|:---|:---|:---|:---|   
| ✔️ [flash_attn_mma_stages_split_kv*](./kernels/flash-attn/mma/flash_attn_mma_split_kv.cu)|f16|f16|[link](./kernels/flash-attn)|⭐️⭐️⭐️⭐️| 
| ✔️ [flash_attn_mma_stages_split_q*](./kernels/flash-attn/mma/flash_attn_mma_split_q.cu)|f16|f16|[link](./kernels/flash-attn)|⭐️⭐️⭐️⭐️|   
| ✔️ [flash_attn_mma_stages...shared_kv*](./kernels/flash-attn/mma/flash_attn_mma_share_kv.cu)|f16|f16|[link](./kernels/flash-attn)|⭐️⭐️⭐️⭐️⭐️|   
| ✔️ [flash_attn_mma_stages...shared_qkv*](./kernels/flash-attn/mma/flash_attn_mma_share_qkv.cu)|f16|f16|[link](./kernels/flash-attn)|⭐️⭐️⭐️⭐️⭐️|   
| ✔️ [flash_attn_mma_stages...tiling_qk*](./kernels/flash-attn/mma/flash_attn_mma_tiling_qk.cu)|f16|f16|[link](./kernels/flash-attn)|⭐️⭐️⭐️⭐️⭐️|   
| ? [flash_attn_mma_stages_split_kv{f32}*](./kernels/flash-attn/mma/flash_attn_mma_split_kv_acc_f32.cu)|f16|f32|[link](./kernels/flash-attn)|⭐️⭐️⭐️⭐️| 
| ? [flash_attn_mma_stages_split_q{f32}*](./kernels/flash-attn/mma/flash_attn_mma_split_q_acc_f32.cu)|f16|f32|[link](./kernels/flash-attn)|⭐️⭐️⭐️⭐️|   
| ? [flash_attn_mma_stages...shared_kv{f32}*](./kernels/flash-attn/mma/flash_attn_mma_share_kv_acc_f32.cu)|f16|f32|[link](./kernels/flash-attn)|⭐️⭐️⭐️⭐️⭐️|   
| ? [flash_attn_mma_stages...shared_qkv{f32}*](./kernels/flash-attn/mma/flash_attn_mma_share_qkv_acc_f32.cu)|f16|f32|[link](./kernels/flash-attn)|⭐️⭐️⭐️⭐️⭐️|   
| ? [flash_attn_mma_stages...tiling_qk{f32}*](./kernels/flash-attn/mma/flash_attn_mma_tiling_qk_acc_f32.cu)|f16|f32|[link](./kernels/flash-attn)|⭐️⭐️⭐️⭐️⭐️|   
## 📖 博客目录

<div id="my-blogs-part-1"></div>  

### 📚 大模型|多模态|Diffusion|推理优化 (本人作者) ([©️back👆🏻](#contents))

|📖 类型-标题|📖 作者|
|:---|:---| 
|[[分布式训推][张量/序列并行]📖图解DeepSpeed-Ulysses&Megatron-LM TP/SP](https://zhuanlan.zhihu.com/p/5750410146)|@DefTruth|
|[[VLM推理优化][InternVL系列]📖InternLM2/.../InternVL1.5系列笔记: 核心点解析](https://zhuanlan.zhihu.com/p/702481058)|@DefTruth|
|[[LLM推理优化][TensorRT-LLM][5w字]📖TensorRT-LLM部署调优-指北](https://zhuanlan.zhihu.com/p/699333691)|@DefTruth|
|[[LLM推理优化][KV Cache优化]📖GQA/YOCO/CLA/MLKV: 层内和层间KV Cache共享](https://zhuanlan.zhihu.com/p/697311739)|@DefTruth|
|[[LLM推理优化][Prefill优化]📖图解vLLM Prefix Prefill Triton Kernel](https://zhuanlan.zhihu.com/p/695799736)|@DefTruth|
|[[LLM推理优化][Prefill优化][万字]📖图解vLLM Automatic Prefix Caching: TTFT优化](https://zhuanlan.zhihu.com/p/693556044)|@DefTruth|
|[[LLM推理优化][Attention优化]📖图解:从Online-Softmax到FlashAttention V1/V2/V3](https://zhuanlan.zhihu.com/p/668888063)|@DefTruth|
|[[LLM推理优化][Decoding优化]📖原理&图解FlashDecoding/FlashDecoding++](https://zhuanlan.zhihu.com/p/696075602)|@DefTruth|
|[[VLM推理优化][LLaVA系列]📖CLIP/LLaVA/LLaVA1.5/VILA笔记: 核心点解析](https://zhuanlan.zhihu.com/p/683137074)|@DefTruth|
|[[LLM推理优化][Attention优化][万字]📖TensorRT MHA/Myelin vs FlashAttention-2](https://zhuanlan.zhihu.com/p/678873216)|@DefTruth|
|[[LLM推理优化][PTX汇编]📖CUDA 12 PTX汇编: PRMT指令详解-通用模式](https://zhuanlan.zhihu.com/p/660630414)|@DefTruth|
|[[LLM推理优化][PTX汇编]📖CUDA 12 PTX汇编: LOP3指令详解](https://zhuanlan.zhihu.com/p/659741469)|@DefTruth|
|[[LLM推理优化][CUDA][3w字]📖高频面试题汇总-大模型手撕CUDA](https://zhuanlan.zhihu.com/p/678903537)|@DefTruth|
|[[LLM推理优化][Weight Only]📖WINT8/4-(00): 通俗易懂讲解-快速反量化算法](https://zhuanlan.zhihu.com/p/657072856)|@DefTruth|
|[[LLM推理优化][Weight Only]📖WINT8/4-(01): PRMT指令详解及FT源码解析](https://zhuanlan.zhihu.com/p/657070837)|@DefTruth|
|[[LLM推理优化][Weight Only]📖WINT8/4-(02): 快速反量化之INT8转BF16](https://zhuanlan.zhihu.com/p/657073159)|@DefTruth|
|[[LLM推理优化][Weight Only]📖WINT8/4-(03): LOP3指令详解及INT4转FP16/BF16](https://zhuanlan.zhihu.com/p/657073857)|@DefTruth|
|[[LLM推理优化][LLM Infra整理]📖100+篇: 大模型推理各方向新发展整理](https://zhuanlan.zhihu.com/p/693680304)|@DefTruth|
|[[LLM推理优化][LLM Infra整理]📖30+篇: LLM推理论文集-500页PDF](https://zhuanlan.zhihu.com/p/669777159)|@DefTruth|
|[[LLM推理优化][LLM Infra整理]📖FlashDecoding++: 比FlashDecoding还要快！](https://zhuanlan.zhihu.com/p/665022589)|@DefTruth|
|[[LLM推理优化][LLM Infra整理]📖TensorRT-LLM开源，TensorRT 9.1也来了](https://zhuanlan.zhihu.com/p/662361469)|@DefTruth|
|[[LLM推理优化][LLM Infra整理]📖20+篇: LLM推理论文集-300页PDF](https://zhuanlan.zhihu.com/p/658091768)|@DefTruth|
|[[LLM推理优化][LLM Infra整理]📖PagedAttention论文新鲜出炉](https://zhuanlan.zhihu.com/p/617015570)|@DefTruth|


### 📚 CV推理部署|C++|算法|技术随笔 (本人作者) ([©️back👆🏻](#contents))

<div id="my-blogs-part-2"></div>  

|📖 类型-标题|📖 作者|
|:---|:---| 
| [[推理部署][CV/NLP]📖FastDeploy三行代码搞定150+ CV、NLP模型部署](https://zhuanlan.zhihu.com/p/581326442)|@DefTruth|  
| [[推理部署][CV]📖如何在lite.ai.toolkit(3.6k+ stars)中增加您的模型？](https://zhuanlan.zhihu.com/p/523876625)|@DefTruth|  
| [[推理部署][CV]📖美团 YOLOv6 ORT/MNN/TNN/NCNN C++推理部署](https://zhuanlan.zhihu.com/p/533643238)|@DefTruth|  
| [[推理部署][ONNX]📖ONNX推理加速技术文档-杂记](https://zhuanlan.zhihu.com/p/524023964)|@DefTruth|  
| [[推理部署][TensorFlow]📖Mac源码编译TensorFlow C++指北](https://zhuanlan.zhihu.com/p/524013615)|@DefTruth|  
| [[推理部署][CV]📖1Mb!头部姿态估计: FSANet，一个小而美的模型(C++)](https://zhuanlan.zhihu.com/p/447364201)|@DefTruth|  
| [[推理部署][CV]📖opencv+ffmpeg编译打包全解指南](https://zhuanlan.zhihu.com/p/472115312)|@DefTruth|  
| [[推理部署][CV]📖RobustVideoMatting视频抠图静态ONNX模型转换](https://zhuanlan.zhihu.com/p/459088407)|@DefTruth|  
| [[推理部署][CV]📖190Kb!SSRNet年龄检测详细解读（含C++工程）](https://zhuanlan.zhihu.com/p/462762797)|@DefTruth|  
| [[推理部署][CV]📖MGMatting(CVPR2021)人像抠图C++应用记录](https://zhuanlan.zhihu.com/p/464732042)|@DefTruth|  
| [[推理部署][CV]📖超准确人脸检测(带关键点)YOLO5Face C++工程详细记录](https://zhuanlan.zhihu.com/p/461878005)|@DefTruth|  
| [[推理部署][ORT]📖解决: ONNXRuntime(Python) GPU 部署配置记录](https://zhuanlan.zhihu.com/p/457484536)|@DefTruth|  
| [[推理部署][CV]📖记录SCRFD(CVPR2021)人脸检测C++工程化(含docker镜像)](https://zhuanlan.zhihu.com/p/455165568)|@DefTruth|  
| [[推理部署][NCNN]📖野路子：记录一个解决onnx转ncnn时op不支持的trick](https://zhuanlan.zhihu.com/p/451446147)|@DefTruth|  
| [[推理部署][CV]📖升级版轻量级NanoDet-Plus MNN/TNN/NCNN/ORT C++工程记录](https://zhuanlan.zhihu.com/p/450586647)|@DefTruth|  
| [[推理部署][CV]📖超轻量级NanoDet MNN/TNN/NCNN/ORT C++工程记录](https://zhuanlan.zhihu.com/p/443419387)|@DefTruth|  
| [[推理部署][CV]📖详细记录MGMatting之MNN、TNN和ORT C++移植](https://zhuanlan.zhihu.com/p/442949027)|@DefTruth|  
| [[推理部署][CV]📖YOLOX NCNN/MNN/TNN/ONNXRuntime C++工程简记](https://zhuanlan.zhihu.com/p/447364122)|@DefTruth|  
| [[推理部署][TNN]📖手动修改YoloX的tnnproto记录-TNN](https://zhuanlan.zhihu.com/p/425668734)|@DefTruth|  
| [[推理部署][ORT]📖全网最详细 ONNXRuntime C++/Java/Python 资料！](https://zhuanlan.zhihu.com/p/414317269)|@DefTruth|  
| [[推理部署][CV]📖RobustVideoMatting: C++工程化记录-实现篇](https://zhuanlan.zhihu.com/p/413280488)|@DefTruth|  
| [[推理部署][CV]📖RobustVideoMatting: C++工程化记录-应用篇](https://zhuanlan.zhihu.com/p/412491918)|@DefTruth|  
| [[推理部署][ORT]📖ONNXRuntime C++ CMake 工程分析及编译](https://zhuanlan.zhihu.com/p/411887386)|@DefTruth|  
| [[推理部署][ORT]📖如何使用ORT C++ API处理NCHW和NHWC输入？](https://zhuanlan.zhihu.com/p/524230808)|@DefTruth|  
| [[推理部署][TNN]📖tnn-convert搭建简记-YOLOP转TNN](https://zhuanlan.zhihu.com/p/431418709)|@DefTruth|  
| [[推理部署][CV]📖YOLOP ONNXRuntime C++工程化记录](https://zhuanlan.zhihu.com/p/411651933)|@DefTruth|  
| [[推理部署][NCNN]📖超有用NCNN参考资料整理](https://zhuanlan.zhihu.com/p/449765328)|@DefTruth|  
| [[推理部署][MNN]📖超有用MNN参考资料整理](https://zhuanlan.zhihu.com/p/449761992)|@DefTruth|  
| [[推理部署][TNN]📖超有用TNN参考资料整理](https://zhuanlan.zhihu.com/p/449769615)|@DefTruth|  
| [[推理部署][ONNX]📖超有用ONNX参考资料整理](https://zhuanlan.zhihu.com/p/449773663)|@DefTruth|  
| [[推理部署][ONNX]📖超有用ONNX模型结构参考资料整理](https://zhuanlan.zhihu.com/p/449775926)|@DefTruth|  
| [[推理部署][OpenCV-DNN]📖超有用OpenCV-DNN参考资料整理](https://zhuanlan.zhihu.com/p/449778377)|@DefTruth|  
| [[推理部署][Tensorflow]📖超有用Tensorflow C++工程化知识点](https://zhuanlan.zhihu.com/p/449788027)|@DefTruth|  
| [[推理部署][模型转换]📖深度学习模型转换资料整理](https://zhuanlan.zhihu.com/p/449759361)|@DefTruth|  
| [[技术随笔][C++][CMake]📖超有用CMake参考资料整理](https://zhuanlan.zhihu.com/p/449779892)|@DefTruth|  
| [[技术随笔][C++][3W字]📖静态链接和静态库实践指北-原理篇](https://zhuanlan.zhihu.com/p/595527528)|@DefTruth|  
| [[技术随笔][C++]📖Mac下C++内存检查指北(Valgrind VS Asan)](https://zhuanlan.zhihu.com/p/508470880)|@DefTruth|  
| [[技术随笔][CV]📖torchlm: 人脸关键点检测库](https://zhuanlan.zhihu.com/p/467211561)|@DefTruth|  
| [[技术随笔][ML]📖《统计学习方法-李航: 笔记-从原理到实现-基于R》](https://zhuanlan.zhihu.com/p/684885595)|@DefTruth|  
| [[技术随笔][Git]📖如何优雅地git clone和git submodule？](https://zhuanlan.zhihu.com/p/639136221)|@DefTruth|  
| [[技术随笔][3D]📖人脸重建3D参考资料整理](https://zhuanlan.zhihu.com/p/524034741)|@DefTruth|  
| [[技术随笔][3D]📖BlendShapes参考资料整理](https://zhuanlan.zhihu.com/p/524036145)|@DefTruth|  
| [[技术随笔][3D]📖从源码安装Pytorch3D详细记录及学习资料](https://zhuanlan.zhihu.com/p/512347464)|@DefTruth|  
| [[技术随笔][ML]📖200页:《统计学习方法：李航》笔记 -从原理到实现](https://zhuanlan.zhihu.com/p/461520847)|@DefTruth|  


### 📚 CUTLASS|CuTe|NCCL|CUDA|文章推荐 (其他作者) ([©️back👆🏻](#contents))

<div id="other-blogs"></div>  

💡说明: 本小节整理一些自己比较喜欢的文章。欢迎大家提PR推荐更多优秀的文章！

|📖 类型-标题|📖 作者|
|:---|:---| 
| [[cute系列详解][入门]📖cutlass cute 101](https://zhuanlan.zhihu.com/p/660379052)|@朱小霖|
| [[cute系列详解][入门]📖CUTLASS 2.x & CUTLASS 3.x Intro 学习笔记](https://zhuanlan.zhihu.com/p/710516489)|@BBuf|
| [[cute系列详解][Layout]📖cute 之 Layout](https://zhuanlan.zhihu.com/p/661182311)|@reed|
| [[cute系列详解][Layout]📖cute Layout 的代数和几何解释](https://zhuanlan.zhihu.com/p/662089556)|@reed|
| [[cute系列详解][Tensor]📖cute 之 Tensor](https://zhuanlan.zhihu.com/p/663093816)|@reed|
| [[cute系列详解][MMA]📖cute 之 MMA抽象](https://zhuanlan.zhihu.com/p/663092747)|@reed|
| [[cute系列详解][Copy]📖cute 之 Copy抽象](https://zhuanlan.zhihu.com/p/666232173)|@reed|
| [[cute系列详解][Swizzle]📖cute 之 Swizzle](https://zhuanlan.zhihu.com/p/671419093)|@reed|
| [[cute系列详解][Swizzle]📖cute Swizzle细谈](https://zhuanlan.zhihu.com/p/684250988)|@进击的Killua|
| [[cute系列详解][Swizzle]📖cutlass swizzle机制解析（一）](https://zhuanlan.zhihu.com/p/710337546)|@Titus|
| [[cute系列详解][Swizzle]📖cutlass swizzle机制解析（二）](https://zhuanlan.zhihu.com/p/711398930)|@Titus|
| [[cute系列详解][GEMM]📖cute 之 简单GEMM实现](https://zhuanlan.zhihu.com/p/667521327)|@reed|
| [[cute系列详解][GEMM]📖cute 之 GEMM流水线](https://zhuanlan.zhihu.com/p/665082713)|@reed|
| [[cute系列详解][GEMM]📖cute 之 高效GEMM实现](https://zhuanlan.zhihu.com/p/675308830)|@reed|
| [[cute系列详解][GEMM]📖GEMM流水线: single/multi-stage、pipeline](https://zhuanlan.zhihu.com/p/712451053)|@Titus|
| [[cute系列详解][GEMM]📖GEMM细节分析(一): ldmatrix的选择](https://zhuanlan.zhihu.com/p/702818267)|@Anonymous|
| [[cute系列详解][GEMM]📖GEMM细节分析(二): TiledCopy与cp.async](https://zhuanlan.zhihu.com/p/703560147)|@Anonymous|
| [[cute系列详解][GEMM]📖GEMM细节分析(三): Swizzle<B,M,S>参数取值](https://zhuanlan.zhihu.com/p/713713957)|@Anonymous|
| [[cute系列详解][实践]📖Hopper Mixed GEMM的CUTLASS实现笔记](https://zhuanlan.zhihu.com/p/714378343)|@BBuf|
| [[cute系列详解][实践]📖CUTLASS CuTe实战(一): 基础](https://zhuanlan.zhihu.com/p/690703999)|@进击的Killua|
| [[cute系列详解][实践]📖CUTLASS CuTe实战(二): 应用](https://zhuanlan.zhihu.com/p/692078624)|@进击的Killua|
| [[cute系列详解][实践]📖FlashAttention fp8实现（ada架构)](https://zhuanlan.zhihu.com/p/712314257)|@shengying.wei|
| [[cute系列详解][实践]📖FlashAttention 笔记: tiny-flash-attention解读](https://zhuanlan.zhihu.com/p/708867810)|@shengying.wei|
| [[cute系列详解][实践]📖使用cutlass cute复现flash attention](https://zhuanlan.zhihu.com/p/696323042)|@66RING|
| [[cutlass教程][入门]📖cutlass 基本认知](https://zhuanlan.zhihu.com/p/677616101)|@JoeNomad|
| [[cutlass教程][入门]📖cutlass 软件架构](https://zhuanlan.zhihu.com/p/678915618)|@JoeNomad|
| [[cutlass教程][入门]📖CUTLASS 基础介绍](https://zhuanlan.zhihu.com/p/671324125)|@进击的Killua|
| [[cutlass教程][入门]📖乱谈CUTLASS GTC2020 SLIDES](https://zhuanlan.zhihu.com/p/674693873)|@zzk again|
| [[cutlass教程][深入]📖cutlass block swizzle 和 tile iterator](https://zhuanlan.zhihu.com/p/679929705)|@JoeNomad|
| [[cutlass教程][深入]📖cutlass bank conflict free的smem layout](https://zhuanlan.zhihu.com/p/681966685)|@JoeNomad|
| [[cutlass教程][深入]📖cutlass 多级流水线](https://zhuanlan.zhihu.com/p/687397095)|@JoeNomad|
| [[GPU指令集架构][精解]📖NVidia GPU指令集架构-前言](https://zhuanlan.zhihu.com/p/686198447)|@reed|
| [[GPU指令集架构][精解]📖NVidia GPU指令集架构-寄存器](https://zhuanlan.zhihu.com/p/688616037)|@reed|
| [[GPU指令集架构][精解]📖NVidia GPU指令集架构-Load和Cache](https://zhuanlan.zhihu.com/p/692445145)|@reed|
| [[GPU指令集架构][精解]📖NVidia GPU指令集架构-浮点运算](https://zhuanlan.zhihu.com/p/695667044)|@reed|
| [[GPU指令集架构][精解]📖NVidia GPU指令集架构-整数运算](https://zhuanlan.zhihu.com/p/700921948)|@reed|
| [[GPU指令集架构][精解]📖NVidia GPU指令集架构-比特和逻辑操作](https://zhuanlan.zhihu.com/p/712356884)|@reed|
| [[CUDA优化][入门]📖CUDA（一）：CUDA 编程基础](https://zhuanlan.zhihu.com/p/645330027)|@紫气东来|
| [[CUDA优化][入门]📖CUDA（二）：GPU的内存体系及其优化指南](https://zhuanlan.zhihu.com/p/654027980)|@紫气东来|
| [[CUDA优化][实践]📖CUDA（三）：通用矩阵乘法：从入门到熟练](https://zhuanlan.zhihu.com/p/657632577)|@紫气东来|
| [[CUDA优化][实践]📖ops(1)：LayerNorm 算子的 CUDA 实现与优化](https://zhuanlan.zhihu.com/p/694974164)|@紫气东来|
| [[CUDA优化][实践]📖ops(2)：SoftMax算子的 CUDA 实现](https://zhuanlan.zhihu.com/p/695307283)|@紫气东来|
| [[CUDA优化][实践]📖ops(3)：Cross Entropy 的 CUDA 实现](https://zhuanlan.zhihu.com/p/695594396)|@紫气东来|
| [[CUDA优化][实践]📖ops(4)：AdamW 优化器的 CUDA 实现](https://zhuanlan.zhihu.com/p/695611950)|@紫气东来|
| [[CUDA优化][实践]📖ops(5)：激活函数与残差连接的 CUDA 实现](https://zhuanlan.zhihu.com/p/695703671)|@紫气东来|
| [[CUDA优化][实践]📖ops(6)：embedding 层与 LM head 层的 CUDA 实现](https://zhuanlan.zhihu.com/p/695785781)|@紫气东来|
| [[CUDA优化][实践]📖ops(7)：self-attention 的 CUDA 实现及优化 (上)](https://zhuanlan.zhihu.com/p/695898274)|@紫气东来|
| [[CUDA优化][实践]📖ops(8)：self-attention 的 CUDA 实现及优化 (下)](https://zhuanlan.zhihu.com/p/696197013)|@紫气东来|
| [[CUDA优化][实践]📖CUDA（四）：使用 CUDA 实现 Transformer 结构](https://zhuanlan.zhihu.com/p/694416583)|@紫气东来|
| [[CUDA优化][Copy]📖Async Copy及Memory Barrier指令的功能与实现](https://zhuanlan.zhihu.com/p/685168850)|@Frank Wang|
| [[CUDA优化][GEMV]📖深入浅出GPU优化系列：gemv优化](https://zhuanlan.zhihu.com/p/494144694)|@有了琦琦的棍子|
| [[Tensor Cores]📖Nvidia Tensor Core初探](https://zhuanlan.zhihu.com/p/620185229)|@木子知|
| [[Tensor Cores]📖Nvidia Tensor Core-WMMA API编程入门](https://zhuanlan.zhihu.com/p/620766588)|@木子知|
| [[Tensor Cores]📖Nvidia Tensor Core-MMA PTX编程入门](https://zhuanlan.zhihu.com/p/621855199)|@木子知|
| [[Tensor Cores]📖CUDA Ampere Tensor Core HGEMM 矩阵乘法优化](https://zhuanlan.zhihu.com/p/555339335)|@nicholaswilde|
| [[GPU通信架构][精解]📖NVIDIA GPGPU（四）- 通信架构](https://zhuanlan.zhihu.com/p/680262016)|@Bruce|


## ©️License ([©️back👆🏻](#contents))

<div id="License"></div>  

GNU General Public License v3.0

## 🎉Contribute ([©️back👆🏻](#contents))

<div id="Contribute"></div>  

How to contribute? Star this repo or check [🌤🌤CONTRIBUTE🎉🎉](https://github.com/DefTruth/CUDA-Learn-Notes/issues/50). 

<div align='center'>
<a href="https://star-history.com/#DefTruth/CUDA-Learn-Notes&Date">
 <picture>
   <source media="(prefers-color-scheme: dark)" srcset="https://api.star-history.com/svg?repos=DefTruth/CUDA-Learn-Notes&type=Date&theme=dark" />
   <source media="(prefers-color-scheme: light)" srcset="https://api.star-history.com/svg?repos=DefTruth/CUDA-Learn-Notes&type=Date" />
   <img img width=450 height=300 alt="Star History Chart" src="https://api.star-history.com/svg?repos=DefTruth/CUDA-Learn-Notes&type=Date" />
 </picture>
</a>
</div>

## 📖 References ([©️back👆🏻](#contents))
- [flash-attention-minimal](https://github.com/tspeterkim/flash-attention-minimal)
- [tiny-flash-attention](https://github.com/66RING/tiny-flash-attention)
- [cute-gemm](https://github.com/reed-lau/cute-gemm)
- [cutlass_flash_atten_fp8](https://github.com/weishengying/cutlass_flash_atten_fp8)
- [cuda_learning](https://github.com/ifromeast/cuda_learning)
- [cuda_hgemm](https://github.com/Bruce-Lee-LY/cuda_hgemm)
- [cuda-tensorcore-hgemm](https://github.com/nicolaswilde/cuda-tensorcore-hgemm)
- [How_to_optimize_in_GPU](https://github.com/Liu-xiandong/How_to_optimize_in_GPU/tree/master/sgemv)
- [cute_gemm](https://github.com/weishengying/cute_gemm)
- [cutlass](https://github.com/NVIDIA/cutlass)

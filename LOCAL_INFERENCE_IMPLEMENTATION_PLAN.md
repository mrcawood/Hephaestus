# Local GLM-4.6 Inference Implementation Plan
## Multi-Node GH200 Deployment for Hephaestus

**Date Created:** 2025-11-14  
**Target Hardware:** Multiple NVIDIA GH200 nodes (97.8GB GPU memory each)  
**Model:** GLM-4.6 (355B parameter MoE model)  
**Purpose:** Eliminate cloud API costs by running inference locally

---

## Overview

This plan outlines the steps to deploy GLM-4.6 locally on multiple GH200 nodes and integrate it with Hephaestus to replace cloud inference providers (Novita AI, OpenAI, etc.).

### Current State
- **Cloud Provider:** Novita AI (GLM-4.6 via Anthropic-compatible API)
- **Cost Issue:** API rate limits and costs mounting
- **Hardware:** Multiple GH200 nodes available (97.8GB GPU memory each)
- **Model:** GLM-4.6-AWQ (~184GB) or FP8 quantized (~92GB)

### Target State
- **Local Inference:** GLM-4.6 running on multi-node GH200 cluster
- **Integration:** Hephaestus configured to use local endpoint
- **Cost Savings:** ~95% reduction (only embeddings remain cloud-based)

---

## Phase 1: Hardware Assessment & Preparation

### 1.1 Verify Hardware Setup
- [ ] Confirm number of GH200 nodes available
- [ ] Verify network connectivity between nodes (NVLink/InfiniBand/Ethernet)
- [ ] Check CUDA version compatibility (need CUDA 12.0+)
- [ ] Verify driver version (580.95.05 confirmed)
- [ ] Test inter-node network latency (<1ms ideal)

### 1.2 Memory Requirements Analysis
- [ ] Calculate exact memory needs:
  - FP8 quantized: ~92GB
  - AWQ quantized: ~184GB
  - Full precision: ~700GB+ (not feasible)
- [ ] Determine minimum nodes needed:
  - 2 nodes (195.6GB): FP8 quantization required
  - 4 nodes (391.2GB): Can run AWQ or BF16
  - 8+ nodes: Full precision possible

### 1.3 Network Configuration
- [ ] Configure high-speed interconnect (NVLink preferred)
- [ ] Set up Ray cluster networking
- [ ] Test bandwidth between nodes (target: >100 Gbps)
- [ ] Configure firewall rules for Ray and vLLM ports

---

## Phase 2: Software Environment Setup

### 2.1 Install Dependencies on All Nodes

```bash
# On each GH200 node:

# 1. Install Python 3.10+ (if not already installed)
python3 --version  # Verify 3.10+

# 2. Create virtual environment
python3 -m venv ~/vllm_env
source ~/vllm_env/bin/activate

# 3. Install CUDA toolkit (if needed)
# Verify: nvidia-smi shows CUDA 13.0

# 4. Install vLLM with CUDA support
pip install --upgrade pip
pip install vllm[all]>=0.10.2

# 5. Install Ray for distributed execution
pip install "ray[default]>=2.8.0"

# 6. Install additional dependencies
pip install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu121
pip install transformers accelerate
```

### 2.2 Verify Installation
- [ ] Test vLLM import: `python3 -c "import vllm; print(vllm.__version__)"`
- [ ] Test Ray: `ray --version`
- [ ] Test CUDA access: `python3 -c "import torch; print(torch.cuda.is_available())"`
- [ ] Verify GPU visibility: `nvidia-smi` shows all GPUs

---

## Phase 3: Model Download & Preparation

### 3.1 Download GLM-4.6 Model

**Option A: FP8 Quantized (Recommended for 2 nodes)**
```bash
# On master node with sufficient disk space
# Model will be ~92GB

# Using Hugging Face
huggingface-cli download THUDM/GLM-4.6 --local-dir ~/models/GLM-4.6

# Or using ModelScope (alternative)
# pip install modelscope
# from modelscope import snapshot_download
# snapshot_download('THUDM/GLM-4.6', cache_dir='~/models')
```

**Option B: AWQ Quantized (For 4+ nodes)**
```bash
huggingface-cli download QuantTrio/GLM-4.6-AWQ --local-dir ~/models/GLM-4.6-AWQ
```

### 3.2 Verify Model Files
- [ ] Check model directory structure
- [ ] Verify all checkpoint files present
- [ ] Test model loading: `python3 -c "from transformers import AutoModel; AutoModel.from_pretrained('~/models/GLM-4.6')"`

---

## Phase 4: Multi-Node Ray Cluster Setup

### 4.1 Start Ray Cluster

**On Node 0 (Head Node):**
```bash
source ~/vllm_env/bin/activate

# Start Ray head node
ray start --head \
    --port=6379 \
    --dashboard-host=0.0.0.0 \
    --dashboard-port=8265 \
    --node-ip-address=<NODE0_IP> \
    --num-cpus=$(nproc) \
    --num-gpus=$(nvidia-smi --list-gpus | wc -l)

# Note the Ray address (will be displayed)
# Example: ray://<NODE0_IP>:6379
```

**On Node 1, 2, 3... (Worker Nodes):**
```bash
source ~/vllm_env/bin/activate

# Connect to head node
ray start --address=<NODE0_IP>:6379 \
    --node-ip-address=<THIS_NODE_IP> \
    --num-cpus=$(nproc) \
    --num-gpus=$(nvidia-smi --list-gpus | wc -l)
```

### 4.2 Verify Ray Cluster
- [ ] Check Ray dashboard: `http://<NODE0_IP>:8265`
- [ ] Verify all nodes visible: `ray status`
- [ ] Test distributed execution: `ray exec ray://<NODE0_IP>:6379 "nvidia-smi"`

---

## Phase 5: vLLM Multi-Node Deployment

### 5.1 Configuration for 2 Nodes (FP8 Quantized)

**On Master Node:**
```bash
source ~/vllm_env/bin/activate

# Set environment variables
export CUDA_VISIBLE_DEVICES=0
export RAY_ADDRESS="ray://<NODE0_IP>:6379"

# Launch vLLM server
vllm serve \
    ~/models/GLM-4.6 \
    --quantization fp8 \
    --tensor-parallel-size 2 \
    --enable-expert-parallel \
    --expert-parallel-size 2 \
    --gpu-memory-utilization 0.85 \
    --max-model-len 32768 \
    --max-num-seqs 64 \
    --swap-space 16 \
    --host 0.0.0.0 \
    --port 8001 \
    --trust-remote-code \
    --disable-log-requests \
    --distributed-executor-backend ray
```

### 5.2 Configuration for 4 Nodes (AWQ or BF16)

```bash
vllm serve \
    ~/models/GLM-4.6-AWQ \
    --tensor-parallel-size 4 \
    --enable-expert-parallel \
    --expert-parallel-size 4 \
    --gpu-memory-utilization 0.9 \
    --max-model-len 131072 \
    --max-num-seqs 128 \
    --host 0.0.0.0 \
    --port 8001 \
    --trust-remote-code \
    --distributed-executor-backend ray
```

### 5.3 Verify vLLM Deployment
- [ ] Check vLLM logs for successful startup
- [ ] Test API endpoint: `curl http://<NODE0_IP>:8001/health`
- [ ] Test inference: `curl http://<NODE0_IP>:8001/v1/completions -H "Content-Type: application/json" -d '{"model":"GLM-4.6","prompt":"Hello","max_tokens":10}'`
- [ ] Monitor GPU memory usage: `nvidia-smi` on all nodes
- [ ] Check Ray dashboard for worker status

---

## Phase 6: Hephaestus Integration

### 6.1 Update Hephaestus Configuration

**Option A: Use Claude Code with Local Endpoint**

Update `hephaestus_config.yaml`:
```yaml
agents:
  default_cli_tool: claude
  cli_model: GLM-4.6
  glm_api_base_url: http://<NODE0_IP>:8001/v1  # Local vLLM endpoint
  glm_model_name: GLM-4.6
  glm_api_token_env: ""  # Not needed for local
```

**Option B: Add Local Provider to LangChain**

1. Update `src/interfaces/langchain_llm_client.py`:
```python
elif provider == "local_glm":
    from langchain_openai import ChatOpenAI
    return ChatOpenAI(
        model="GLM-4.6",
        base_url=f"{provider_config.base_url}/v1",
        api_key="not-needed",  # vLLM doesn't require auth
        temperature=assignment.temperature,
        max_tokens=assignment.max_tokens
    )
```

2. Update `hephaestus_config.yaml`:
```yaml
llm:
  providers:
    local_glm:
      api_key_env: ""  # Not needed
      base_url: "http://<NODE0_IP>:8001"
  model_assignments:
    task_enrichment:
      provider: local_glm
      model: GLM-4.6
      temperature: 0.7
      max_tokens: 4000
    # ... other assignments
```

### 6.2 Test Integration
- [ ] Test task enrichment with local endpoint
- [ ] Test agent prompt generation
- [ ] Test monitoring/guardian analysis
- [ ] Verify all LLM calls use local endpoint
- [ ] Monitor response times (should be 100-500ms)

### 6.3 Keep Embeddings Cloud-Based (Optional)
- [ ] Keep OpenAI embeddings (very cheap: ~$0.0001/1K tokens)
- [ ] Or implement local embeddings with sentence-transformers
- [ ] Update `embedding_provider` in config if switching

---

## Phase 7: Performance Optimization & Monitoring

### 7.1 Performance Tuning
- [ ] Adjust `gpu-memory-utilization` (0.85-0.95)
- [ ] Tune `max-num-seqs` based on batch size needs
- [ ] Optimize `max-model-len` for your use case
- [ ] Test different quantization levels (FP8 vs AWQ vs BF16)

### 7.2 Monitoring Setup
- [ ] Set up GPU monitoring: `nvidia-smi dmon`
- [ ] Monitor Ray dashboard: `http://<NODE0_IP>:8265`
- [ ] Set up vLLM metrics endpoint: `http://<NODE0_IP>:8001/metrics`
- [ ] Create alerts for OOM errors or node failures
- [ ] Track inference latency and throughput

### 7.3 Load Testing
- [ ] Test with single request (baseline latency)
- [ ] Test with concurrent requests (throughput)
- [ ] Test with maximum context length
- [ ] Test with Hephaestus's typical workload
- [ ] Compare performance vs cloud provider

---

## Phase 8: Production Deployment

### 8.1 Service Management
- [ ] Create systemd service for vLLM
- [ ] Create systemd service for Ray head node
- [ ] Set up auto-restart on failure
- [ ] Configure log rotation
- [ ] Set up health checks

### 8.2 High Availability (Optional)
- [ ] Set up load balancer for multiple vLLM instances
- [ ] Configure failover mechanism
- [ ] Set up monitoring and alerting
- [ ] Document recovery procedures

### 8.3 Cost Analysis
- [ ] Calculate electricity costs for local inference
- [ ] Compare to cloud API costs
- [ ] Factor in hardware depreciation
- [ ] Document break-even analysis

---

## Troubleshooting Guide

### Common Issues

**Issue: Out of Memory (OOM)**
- Solution: Reduce `gpu-memory-utilization` or `max-model-len`
- Solution: Use more aggressive quantization (FP8)
- Solution: Add more nodes

**Issue: Slow Inference**
- Solution: Check network latency between nodes
- Solution: Verify NVLink/InfiniBand is working
- Solution: Increase `max-num-seqs` for better batching
- Solution: Use fewer nodes with higher memory utilization

**Issue: Ray Cluster Not Connecting**
- Solution: Check firewall rules
- Solution: Verify network connectivity
- Solution: Check Ray logs: `ray logs`

**Issue: Model Not Loading**
- Solution: Verify model files are complete
- Solution: Check disk space
- Solution: Verify model path is accessible from all nodes

---

## Rollback Plan

If local inference doesn't work:
1. Keep cloud provider configuration in `hephaestus_config.yaml`
2. Switch back by changing `glm_api_base_url` to cloud endpoint
3. No code changes needed - just config update

---

## Success Criteria

- [ ] GLM-4.6 running on multi-node GH200 cluster
- [ ] vLLM serving requests successfully
- [ ] Hephaestus integrated and using local endpoint
- [ ] All LLM calls (except embeddings) use local inference
- [ ] Performance acceptable (<1s latency for typical requests)
- [ ] Cost savings achieved (95%+ reduction)
- [ ] System stable for 24+ hours

---

## Next Steps

1. **Resume on GPU Nodes:** Transfer this plan to the GH200 nodes
2. **Start with Phase 1:** Hardware assessment
3. **Test with 2 Nodes First:** Validate approach before scaling
4. **Iterate:** Adjust configuration based on performance

---

## Resources

- vLLM Documentation: https://docs.vllm.ai/
- Ray Documentation: https://docs.ray.io/
- GLM-4.6 Model Card: https://huggingface.co/THUDM/GLM-4.6
- NVIDIA GH200 Documentation: https://www.nvidia.com/en-us/data-center/grace-hopper-superchip/

---

## Notes

- **Model Size:** GLM-4.6 is large - ensure sufficient disk space (~200GB+)
- **Network:** High-speed interconnect critical for multi-node performance
- **Quantization:** FP8 recommended for 2 nodes, AWQ for 4+ nodes
- **Expert Parallelism:** GLM-4.6's MoE architecture benefits greatly from expert parallelism
- **Start Small:** Test with 2 nodes first, then scale up

---

**Status:** Ready to execute on GPU nodes  
**Estimated Time:** 4-8 hours for full setup and testing  
**Risk Level:** Medium (hardware-dependent, requires testing)


# Fly.io Email Scheduler Architecture

## 🎯 Performance-Based Machine Strategy

### Customer Tiers & Machine Allocation

| Customer Size | Contacts | Machine Type | RAM | Processing Time | Monthly Cost |
|---------------|----------|--------------|-----|-----------------|--------------|
| **Starter** | 1k-10k | `shared-cpu-1x` | 1GB | 1-2 seconds | $2-8 |
| **Growth** | 10k-100k | `shared-cpu-2x` | 2GB | 3-5 seconds | $15 |
| **Business** | 100k-500k | `performance-2x` | 4GB | 8-15 seconds | $50 |
| **Enterprise** | 500k-1M+ | `performance-4x` + workers | 8GB+ | 1-3 minutes | $100-200 |

## 🏗️ Dynamic Scaling Architecture

### Primary Scheduler Machine
```yaml
# fly.toml for main scheduler
app = "email-scheduler-primary"

[build]
  image = "scheduler:latest"

[[vm]]
  size = "performance-4x"  # 8GB RAM, 4 CPUs
  memory = "8gb"
  
[env]
  SCHEDULER_MODE = "primary"
  MAX_CONTACTS_SINGLE = "100000"
  WORKER_MACHINE_TYPE = "performance-2x"
```

### Worker Machine Template  
```yaml
# worker-fly.toml for parallel workers
app = "email-scheduler-worker-{customer_id}"

[[vm]]
  size = "performance-2x"  # 4GB RAM, 2 CPUs  
  memory = "4gb"
  
[env]
  SCHEDULER_MODE = "worker"
  CHUNK_SIZE = "100000"
```

## ⚡ Processing Strategy by Customer Size

### Small-Medium Customers (< 100k contacts)
```
┌─────────────────┐
│ Single Machine  │ performance-2x (4GB)
│ In-Memory       │ 29,831 contacts/sec  
│ Processing      │ 3-5 seconds total
└─────────────────┘
```

### Large Customers (100k-500k contacts)
```
┌─────────────────┐
│ Primary Machine │ performance-4x (8GB)
│ Chunked         │ 100k chunks
│ In-Memory       │ Sequential processing  
└─────────────────┘
```

### Enterprise Customers (500k-1M+ contacts)
```
┌─────────────────┐    ┌─────────────────┐
│ Primary Machine │───▶│ Worker Machine 1│ 100k chunk
│ performance-4x  │    │ performance-2x  │ 29,831/sec
│ (Coordinator)   │    └─────────────────┘
└─────────────────┘    ┌─────────────────┐
         │              │ Worker Machine 2│ 100k chunk  
         └─────────────▶│ performance-2x  │ 29,831/sec
                        └─────────────────┘
                        ┌─────────────────┐
                        │ Worker Machine N│ 100k chunk
                        │ performance-2x  │ 29,831/sec  
                        └─────────────────┘
```

## 🔧 Fly.io Machines API Implementation

### Dynamic Worker Scaling
```javascript
// Scale workers based on contact count
async function scaleForCustomer(contactCount, customerId) {
  if (contactCount < 100000) {
    // Single machine processing
    return await processSingleMachine(customerId, 'performance-2x');
  }
  
  // Calculate required workers
  const chunkSize = 100000;
  const workerCount = Math.ceil(contactCount / chunkSize);
  const maxWorkers = 8; // CPU limit consideration
  
  const actualWorkers = Math.min(workerCount, maxWorkers);
  
  // Spin up worker machines via Fly API
  const workers = [];
  for (let i = 0; i < actualWorkers; i++) {
    const worker = await createWorkerMachine({
      customerId,
      workerId: i,
      machineType: 'performance-2x',
      chunkStart: i * chunkSize,
      chunkEnd: (i + 1) * chunkSize
    });
    workers.push(worker);
  }
  
  return workers;
}

async function createWorkerMachine({ customerId, workerId, machineType, chunkStart, chunkEnd }) {
  const response = await fetch(`https://api.machines.dev/v1/apps/scheduler-${customerId}/machines`, {
    method: 'POST',
    headers: {
      'Authorization': `Bearer ${FLY_API_TOKEN}`,
      'Content-Type': 'application/json'
    },
    body: JSON.stringify({
      config: {
        image: 'scheduler:latest',
        size: machineType,
        env: {
          WORKER_ID: workerId,
          CHUNK_START: chunkStart,
          CHUNK_END: chunkEnd,
          CUSTOMER_ID: customerId,
          SCHEDULER_MODE: 'worker'
        },
        auto_destroy: true, // Clean up after completion
        restart: { policy: 'no' }
      }
    })
  });
  
  return response.json();
}
```

## 💰 Cost Optimization Strategy

### Compute Costs (per processing run)
| Customer Size | Machine Hours | Estimated Cost | 
|---------------|---------------|----------------|
| 1k-10k | 0.001 hours | $0.0001 |
| 10k-100k | 0.002 hours | $0.0005 |
| 100k-500k | 0.005 hours | $0.002 |
| 500k-1M | 0.05 hours (3 min) | $0.02 |

### Monthly Processing Costs
- **Daily scheduling**: Enterprise customer = $0.60/month
- **Weekly scheduling**: Enterprise customer = $0.15/month  
- **Monthly scheduling**: Enterprise customer = $0.02/month

### Machine Lifecycle
```
1. Detect large customer job (500k+ contacts)
2. Spin up worker machines (1-2 minutes)
3. Process chunks in parallel (1-3 minutes)  
4. Aggregate results (30 seconds)
5. Auto-destroy worker machines
6. Total time: 3-6 minutes including spin-up
```

## 🎯 Recommended Machine Configuration

### For Your Use Case:
1. **Primary scheduler**: `performance-4x` (always running)
2. **Worker machines**: `performance-2x` (on-demand)
3. **Auto-scaling**: Based on contact count
4. **Cost control**: Auto-destroy after completion

### Performance Expectations:
- **500k contacts**: 2-3 minutes total (including machine spin-up)
- **1M contacts**: 4-6 minutes total  
- **Parallel efficiency**: ~120k-240k contacts/second
- **Cost per run**: $0.01-0.05 for enterprise customers

## 🚀 Implementation Priority

1. **Start simple**: Single `performance-2x` machine for all customers
2. **Add chunking**: When you hit 100k+ contact customers  
3. **Add workers**: When you hit 500k+ contact customers
4. **Optimize costs**: Fine-tune machine types based on real usage

This gives you the perfect balance of performance, cost, and complexity!
# Dual-Plane Neural Architecture Specification

> **Kernel Philosophy:** *"Everything is a Node"*  
> **Core Model:** Dual-Plane Hybrid (Control Plane + Data Plane)  
> **Target Subsystems:** Inter-Node Messaging, Device Drivers, Framebuffers, Memory Graphs, and Task Coordination.

---

## 1. Architectural Philosophy: *"Everything is a Node"*

Modern operating system kernels have historically centered on a unifying abstraction:
- **UNIX / Linux:** *"Everything is a file"* (Linear byte streams behind a VFS file descriptor table).
- **Plan 9:** *"Everything is a file server"* (Networked 9P protocol trees).
- **Redox OS:** *"Everything is a URL"* (Hierarchical URI resource schemes: `file:`, `event:`, `tcp:`).

### The Low-Level Basic Paradigm
Our microkernel adopts a neural-inspired paradigm:
> ### *"Everything is a Node connected via Synaptic Channels."*

In this architecture, every system resource is a discrete **Node**:
- A hardware device (UART, Framebuffer, NVMe, Keyboard) is a **Device Node**.
- A running thread or service is a **Compute Node**.
- A shared memory pool, buffer, or linear RAM window is a **Memory Node**.
- An event router, compositor, or IPC mailbox is a **Router Node**.

Nodes form a dynamic directed graph resembling a **neural network**. Interactions do not treat resources as dumb sequential byte streams; instead, they operate through **Synapses**—typed, capability-checked communication channels that separate policy decisions from high-speed data flow.

---

## 2. The Dual-Plane Hybrid Engine

Traditional microkernels suffer from the "IPC Tax"—every message exchange requires context switches, permission lookups, and queue serialization. The **Dual-Plane Architecture** eliminates this bottleneck by decoupling the **Control Plane** from the **Data Plane**.

```mermaid
flowchart TB
    subgraph ControlPlane ["Control Plane (Synaptic Topology & Policy)"]
        Registry["Node Registry (Capability & Topology Graph)"]
        Acl["Capability ACL & Policy Engine"]
        Negotiator["Synapse Handshake & Channel Setup"]
        Registry --- Acl
        Acl --- Negotiator
    end

    subgraph DataPlane ["Data Plane (Axonal Fast-Path Data Transfer)"]
        RingBuf["Lock-Free Shared Ring Buffer"]
        DMA["Direct Hardware / MMIO Fast-Path"]
        ZeroCopy["Zero-Copy Window Streaming"]
    end

    subgraph ComputeA ["Node A (Compute: GUI Server)"]
        NodeA["Task State & Context"]
    end

    subgraph DeviceB ["Node B (Device: Linear Framebuffer)"]
        NodeB["Hardware Registers & VRAM"]
    end

    NodeA -.->|"1. Handshake & Caps"| Registry
    NodeB -.->|"1. Register Device"| Registry
    Negotiator ==>|"2. Establish Synapse"| NodeA
    Negotiator ==>|"2. Establish Synapse"| NodeB

    NodeA ===>|"3. Fast-Path Axon (Dirty Rects)"| RingBuf
    RingBuf ===>|"4. Direct Scanline Blit"| NodeB
```

### Plane Responsibilities

| Dimension | Control Plane (The Synapse) | Data Plane (The Axon) |
| :--- | :--- | :--- |
| **Primary Goal** | Security, Topology, Resource Discovery | Throughput, Zero-Copy Transfer, Low Latency |
| **Execution Path** | Capability ACL validation, QoS routing, Lifecycle | Lock-free atomics, MMIO burst writes, Direct Ring Buffers |
| **Intervention** | Only during channel setup, reconfiguration, or fault | Continuous bulk transmission without kernel traps |
| **Synchronization** | Ticket spinlocks, IRQ-save critical sections | Atomic head/tail indices, memory fences (`sfence`/`mfence`) |
| **Analogy** | Dendritic synaptic wiring & neurotransmitter signaling | Axonal action potential propagation |

---

## 3. Node & Synapse Topologies

```mermaid
graph LR
    subgraph NeuralCluster ["Active Kernel Node Graph"]
        KBD[Node 1: Keyboard Driver]
        SCHED[Node 2: SMP Scheduler]
        GUI[Node 3: GUI Compositor]
        FB[Node 4: Framebuffer Driver]
        TERM[Node 5: Serial Terminal]

        KBD -- "Synapse (Input Events)" --> GUI
        GUI -- "Synapse (Burst Blits)" --> FB
        SCHED -. "Control Heartbeat" .-> KBD
        SCHED -. "Control Heartbeat" .-> GUI
        SCHED -. "Control Heartbeat" .-> FB
        GUI -- "Synapse (Logs)" --> TERM
    end
```

### Node Types
1. **`NODE_TYPE_COMPUTE`:** Kernel worker threads, userspace tasks, or scheduler agents.
2. **`NODE_TYPE_DEVICE`:** Hardware controllers managing memory-mapped I/O or ports (UART, VGA, Framebuffer, Storage).
3. **`NODE_TYPE_STORAGE`:** Block caches, filesystems, and ramdisks.
4. **`NODE_TYPE_NETWORK`:** Packet ring buffers, NIC descriptors, and protocol sockets.
5. **`NODE_TYPE_MEMORY`:** Virtual memory spaces, Buddy allocator pools, and dynamic frame mappings.

### Synaptic Capability Flags
Permissions are negotiated at connection time:
- **`CAP_SYNAPSE_READ` (`&H01`):** Consumer permission to pull packets from channel.
- **`CAP_SYNAPSE_WRITE` (`&H02`):** Producer permission to push packets to channel.
- **`CAP_SYNAPSE_NOTIFY` (`&H04`):** Permission to register wake-up hooks on state changes.
- **`CAP_SYNAPSE_DMA` (`&H08`):** Permission to map physical memory directly into the data plane.
- **`CAP_SYNAPSE_ADMIN` (`&H80`):** Authority to sever, redirect, or inspect the synapse topology.

---

## 4. Communication Lifecycle Sequence

```mermaid
sequenceDiagram
    autonumber
    participant App as Node A (Consumer Task)
    participant Ctrl as Kernel Node Registry (Control Plane)
    participant FB as Node B (Framebuffer Driver)
    participant Axon as Synapse Fast-Path (Data Plane)

    Note over App,FB: Phase 1: Control-Plane Negotiation
    FB->>Ctrl: RegisterNode("drivers.display.lfb", TYPE_DEVICE, Caps)
    App->>Ctrl: LookupNode("drivers.display.lfb")
    App->>Ctrl: ConnectSynapse(NodeB, RequestCaps=WRITE|DMA)
    Ctrl->>Ctrl: Validate ACL Tokens & Security Permissions
    Ctrl->>Axon: Allocate Shared Ring / MMIO Mapping
    Ctrl-->>App: Return Synapse Handle (ChannelId)
    Ctrl-->>FB: Notify Connected Peer

    Note over App,FB: Phase 2: Data-Plane Fast-Path Streaming
    loop High-Frame-Rate Streaming (Zero Syscall Overhead)
        App->>Axon: Push Dirty-Rect Pixels (Atomic Head Advance)
        Axon->>FB: Hardware Burst Blit / DMA Scanout
        FB-->>Axon: Atomic Tail Advance
    end

    Note over App,FB: Phase 3: Synaptic Teardown
    App->>Ctrl: DisconnectSynapse(ChannelId)
    Ctrl->>Axon: Flush Buffers & Reclaim Resources
    Ctrl-->>FB: Peer Disconnected Notification
```

---

## 5. Low-Level Basic Implementation Architecture

### Control Plane Interface (`src/node/KernelNode.cls`)
```vb
Namespace Core.Nodes

    Public Enum NodeKind
        NODE_COMPUTE = 1
        NODE_DEVICE  = 2
        NODE_MEMORY   = 3
        NODE_ROUTER   = 4
    End Enum

    <Packed>
    Public Structure NodeDescriptor
        Public NodeId As UInt64
        Public Kind As NodeKind
        Public OwnerPid As UInt64
        Public Name(31) As Byte
        Public Capabilities As UInt32
        Public ActiveSynapses As UInt32
    End Structure

End Namespace
```

### Data Plane Channel Interface (`src/node/SynapseChannel.cls`)
```vb
Namespace Core.Nodes

    Public Class SynapseChannel
        Private channelId As UInt64
        Private sourceNode As UInt64
        Private targetNode As UInt64
        Private permissions As UInt32

        ' Lock-free circular ring buffer pointers
        Private ringPhysAddr As UInt64
        Private ringSize As UInt32
        Private headIndex As UInt32
        Private tailIndex As UInt32

        Public Function SendFast(ByVal dataPtr As Pointer To Byte, ByVal length As UInt32) As Boolean
            ' Fast-path data transfer with atomic index advance
        End Function
    End Class

End Namespace
```

---

## 6. Architectural Advantages

1. **Deterministic Latency:** Zero syscall interrupts during streaming transfers. Graphics compositing and audio streaming run without CPU pipeline flushes.
2. **Modular Granularity:** Drivers and applications can be dynamically rewired like neural circuits without restarting subsystems.
3. **Fine-Grained Capability Isolation:** Nodes cannot forge access to hardware devices without explicit cryptographic or ACL tokens negotiated via the Control Plane.
4. **Natural Hardware Acceleration:** Nodes seamlessly bridge software queues to physical hardware descriptors (e.g., GPU rings, virtio queues, NVMe submission queues).

---

## 7. Operational Verification & Display Output

The Dual-Plane Neural Architecture, BGA hardware graphics mode transition, and Axonal Data Plane packet exchange have been verified in QEMU running with 4 SMP cores and 512MB RAM:

![PRK Dual-Plane Node Kernel 1024x768 Graphics Mode](graphics_mode_dashboard.png)

- **Control Plane Registration:** Node #1000 (`core.kernel`, Compute) and Node #1001 (`drivers.display.lfb`, Device) registered dynamically.
- **Synapse Establishment:** Synapse Channel #5000 connected with capability masks `CAP_SYNAPSE_READ | CAP_SYNAPSE_WRITE`.
- **Axonal Fast-Path Delivery:** Verified packet sequence #1 delivery over lock-free circular ring buffers.
- **Hardware Graphics Mode:** BGA programmed to 1024x768x32 BPP true color mode with RAM double-buffering.


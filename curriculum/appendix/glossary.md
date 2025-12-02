# Glossary

## A

**AI/ML**
Artificial Intelligence / Machine Learning. Computational approaches that enable systems to learn from data and make predictions or decisions.

**API Gateway**
A service that acts as a single entry point for API requests, handling routing, authentication, rate limiting, and load balancing.

## B

**Bare Metal**
Physical server hardware without virtualization layer. Provides maximum performance and direct hardware access.

**Bare Metal Operator (BMO)**
Kubernetes operator that manages bare metal hosts through custom resources, working with Ironic for provisioning.

**BareMetalHost (BMH)**
Custom resource definition representing a physical server in Metal3, including BMC credentials and provisioning state.

**BMaaS**
Bare Metal as a Service. Cloud service model providing dedicated physical servers on demand.

**BMC (Baseboard Management Controller)**
Dedicated processor on server motherboard enabling remote management (power, console, health) independent of the main OS.

## C

**CAPI (Cluster API)**
Kubernetes project providing declarative APIs and tooling to manage cluster lifecycle (create, configure, upgrade, destroy).

**CAPM3 (Cluster API Provider Metal3)**
CAPI infrastructure provider that manages bare metal clusters using Metal3.

**Cloud-Init**
Industry standard for cross-platform cloud instance initialization, handling user creation, package installation, and first-boot scripts.

**CNI (Container Network Interface)**
Specification for configuring Linux container networking, implemented by plugins like Calico, Cilium, Flannel.

**CSI (Container Storage Interface)**
Standard for exposing storage systems to containerized workloads, enabling dynamic volume provisioning.

## D

**DCME (Distributed Container Management Environment)**
k0rdent's architecture for managing Kubernetes clusters across multiple environments from a single control plane.

**DPU (Data Processing Unit)**
Programmable processor (like NVIDIA BlueField) that offloads networking, storage, and security tasks from the CPU.

## F

**Fabric Manager**
NVIDIA software that manages NVSwitch topology, enables GPU-to-GPU communication, and handles fabric partitioning for multi-tenant scenarios.

## G

**GPUDirect RDMA**
NVIDIA technology enabling direct memory access between GPU memory and third-party devices (NICs, storage) without CPU involvement.

**GPUDirect Storage**
Extension of GPUDirect enabling direct data path between GPUs and storage devices, bypassing CPU and system memory.

## H

**HBM (High Bandwidth Memory)**
Stacked memory technology used in modern GPUs, providing significantly higher bandwidth than traditional GDDR memory.

**HGX**
NVIDIA reference design for multi-GPU server baseboard, featuring 8 GPUs connected via NVLink/NVSwitch.

**Hugepages**
Linux memory feature providing larger page sizes (2MB, 1GB) than default 4KB, reducing TLB misses and improving performance for memory-intensive workloads.

## I

**IOMMU (Input/Output Memory Management Unit)**
Hardware that provides memory isolation and address translation for I/O devices, required for secure device passthrough.

**IPA (Ironic Python Agent)**
Software running on bare metal nodes during provisioning, executing Ironic commands for disk operations, imaging, and configuration.

**IPMI (Intelligent Platform Management Interface)**
Industry standard protocol for out-of-band server management. Being superseded by Redfish.

**Ironic**
OpenStack project for bare metal provisioning, managing server lifecycle from discovery through deployment and decommissioning.

## K

**KaaS**
Kubernetes as a Service. Platform providing managed Kubernetes clusters with automated deployment and lifecycle management.

**KubeVirt**
Kubernetes extension enabling VM workloads alongside containers, using KVM for virtualization within pods.

## M

**MaaS**
Models as a Service. Platform for serving ML models via APIs with per-request billing.

**Metal3**
Kubernetes-native bare metal host management project, integrating Ironic with Kubernetes CRDs.

**MIG (Multi-Instance GPU)**
NVIDIA technology partitioning a single GPU into multiple isolated instances, each with dedicated memory and compute.

## N

**NUMA (Non-Uniform Memory Access)**
Multi-processor architecture where memory access time depends on memory location relative to processor. Local memory is faster than remote.

**NVLink**
NVIDIA high-speed GPU interconnect technology, providing much higher bandwidth than PCIe for GPU-to-GPU communication.

**NVSwitch**
NVIDIA switch chip enabling all-to-all GPU connectivity in multi-GPU systems, creating a unified GPU memory fabric.

## O

**OIDC (OpenID Connect)**
Authentication layer on OAuth 2.0, commonly used for SSO and federated identity.

## P

**Passthrough (GPU/Device)**
Virtualization technique giving a VM direct access to a physical device, providing near-native performance.

**PXE (Preboot Execution Environment)**
Network boot protocol allowing computers to boot from network server before (or without) local storage.

## R

**RBAC (Role-Based Access Control)**
Access control method based on user roles and permissions, fundamental to Kubernetes security.

**RDMA (Remote Direct Memory Access)**
Technology enabling direct memory access from one computer to another without involving the operating system.

**Redfish**
Modern REST API standard for server management, replacing IPMI with HTTPS-based operations and JSON data model.

**Run:AI / KAI Scheduler**
GPU-aware Kubernetes scheduler providing advanced features like fractional GPUs, gang scheduling, and fair-share queuing.

## S

**SAML (Security Assertion Markup Language)**
XML-based standard for exchanging authentication data between identity providers and service providers.

**SR-IOV (Single Root I/O Virtualization)**
PCIe standard allowing a single physical device to appear as multiple virtual devices, enabling efficient sharing across VMs.

## T

**Tensor Parallelism**
Technique for distributing large neural network layers across multiple GPUs by splitting weight tensors.

**Tenant**
Isolated organizational unit in multi-tenant platforms, with dedicated resources, users, and network space.

## V

**Vector Database**
Database optimized for storing and querying high-dimensional vectors (embeddings), used in similarity search and RAG applications.

**VFIO (Virtual Function I/O)**
Linux kernel framework for secure device passthrough to userspace, enabling VM access to physical devices.

**vGPU**
Virtual GPU technology allowing multiple VMs to share a single physical GPU through time-slicing.

**vLLM**
High-performance LLM inference engine with PagedAttention for efficient memory management.

**VMaaS**
Virtual Machine as a Service. Cloud service providing on-demand virtual machines.

**vNUMA**
Virtual NUMA topology exposed to guest VMs, enabling NUMA-aware workload optimization inside VMs.

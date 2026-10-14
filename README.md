# k0rdent AI Infrastructure Training

Learn to provision a k0rdent environment, serve a model privately, manage GPU capacity, measure performance and recover a service. The course is for engineers comfortable with Kubernetes and Linux.

## Start here

1. **Get the course.** Clone your own fork/copy with the curriculum-v2-pedagogy branch, or use this checkout for reading:

   ```bash
   git clone --branch curriculum-v2-pedagogy https://github.com/Mirantis-PS/k0rdent-ai-training.git
   cd k0rdent-ai-training
   ```

2. **Prepare your workstation and account.** Open the [course guide — prepare](curriculum/README.md#prepare). It lists tools, access and the environment you need before provisioning.
3. **Start the first lab.** Follow [Provision the management cluster](curriculum/modules/platform-bootstrap/labs/provision-k0rdent.md), then return to the [ordered course guide](curriculum/README.md#build-the-platform) for the next step.
4. **Continue through the AI workshops.** The same guide gives the [GPU entry checks and workshop sequence](curriculum/README.md#run-the-ai-workshops), what to retain between labs, and [how to finish or pause](curriculum/README.md#finish-or-pause).

**Use the course guide as your checklist.** You do not need to read every folder or follow the historical lab numbering. Bare metal, virtualization and other specializations are optional.

## What you can run

The platform labs contain the existing AWS provisioning procedures. Running them requires your own authorized AWS environment and incurs infrastructure costs; there is no hosted lab portal.

The AI workshops are an educational draft with explicit execution prerequisites. The existing GPU baseline uses a four-A10G worker. A cheaper single-GPU profile and the two-worker exercise have not been qualified for this revision. Product-specific k0rdent AI integration still needs authoritative distribution/version sources. Use the [readiness table](curriculum/README.md#check-runtime-readiness) before allocating GPUs; a documented procedure is not a claim that this revision has been live-tested.

## Where to go

| You need to… | Open |
|---|---|
| Take or resume the course | [Course guide](curriculum/README.md) |
| Teach or assess it | [Instructor guide](curriculum/instructor/README.md) |
| Choose an optional specialization | [Extensions](curriculum/extensions/README.md) |
| Look up infrastructure commands | [Infrastructure reference](lab-infrastructure/README.md) |
| Diagnose provisioning problems | [Troubleshooting](lab-infrastructure/docs/troubleshooting.md) |
| Maintain the course or inspect its history | [Maintainer guide](docs/README.md) |

The curriculum contains learning material and exercise assets. Historical syllabi and migration records live under docs; they are not additional learner steps.

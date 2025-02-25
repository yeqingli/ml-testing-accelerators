// Copyright 2021 Google LLC
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     https://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

local common = import '../common.libsonnet';
local experimental = import '../experimental.libsonnet';
local mixins = import 'templates/mixins.libsonnet';
local volumes = import 'templates/volumes.libsonnet';

{
  PyTorchTest:: common.PyTorchTest {
    frameworkPrefix: 'pt-r1.10',
    tpuSettings+: {
      softwareVersion: 'pytorch-1.10',
    },
    imageTag: 'r1.10',
  },
  // pytorch does not use a specific image for pods
  PyTorchTpuVm:: experimental.PyTorchTpuVmMixin {
    local config = self,
    tpuSettings+: {
      softwareVersion: 'tpu-vm-pt-1.10',
    },
  },
  PyTorchXlaDistPodTest:: common.PyTorchXlaDistPodTest {
    frameworkPrefix: 'pt-r1.10',
    tpuSettings+: {
      softwareVersion: 'pytorch-1.10',
    },
    imageTag: 'r1.10',
  },
  PyTorchGkePodTest:: common.PyTorchGkePodTest {
    frameworkPrefix: 'pt-r1.10',
    tpuSettings+: {
      softwareVersion: 'pytorch-1.10',
    },
    imageTag: 'r1.10',
  },
  Functional:: mixins.Functional {
    schedule: '0 7 * * *',
    tpuSettings+: {
      preemptible: false,
    },
  },
  Convergence:: mixins.Convergence {
    // Run 3 times/week.
    schedule: '0 7 * * 1,3,5',
  },
  datasetsVolume: volumes.PersistentVolumeSpec {
    name: 'pytorch-datasets-claim',
    mountPath: '/datasets',
  },
  tpu_vm_1_10_install: |||
    sudo bash /var/scripts/docker-login.sh
    git clone https://github.com/pytorch/pytorch.git -b release/1.10
    cd pytorch
    git clone https://github.com/pytorch/xla.git -b r1.10
    export XRT_TPU_CONFIG='localservice;0;localhost:51011'
    export LD_PRELOAD='/usr/lib/x86_64-linux-gnu/libtcmalloc.so.4'
  |||,
}

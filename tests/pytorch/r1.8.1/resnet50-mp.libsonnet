// Copyright 2020 Google LLC
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

local experimental = import '../experimental.libsonnet';
local common = import 'common.libsonnet';
local mixins = import 'templates/mixins.libsonnet';
local timeouts = import 'templates/timeouts.libsonnet';
local tpus = import 'templates/tpus.libsonnet';
local utils = import 'templates/utils.libsonnet';

{
  local resnet50_MP = common.PyTorchTest {
    modelName: 'resnet50-mp',
    command: [
      'python3',
      'pytorch/xla/test/test_train_mp_imagenet.py',
      '--logdir=$(MODEL_DIR)',
      '--model=resnet50',
      '--num_workers=8',
      '--batch_size=128',
      '--log_steps=200',
    ],
    volumeMap+: {
      datasets: common.datasetsVolume,
    },
    cpu: '90.0',
    memory: '400Gi',
  },

  local functional = common.Functional {
    command+: [
      '--num_epochs=2',
      '--datadir=/datasets/imagenet-mini',
    ],
  },
  local convergence = common.Convergence {
    command+: [
      '--num_epochs=90',
      '--datadir=/datasets/imagenet',
    ],
    metricConfig+: {
      sourceMap+:: {
        tensorboard+: {
          aggregateAssertionsMap+:: {
            'Accuracy/test': {
              FINAL: {
                fixed_value: {
                  comparison: 'GREATER',
                  value: 75.0,
                },
                inclusive_bounds: false,
                wait_for_n_data_points: 0,
              },
            },
          },
        },
      },
    },
  },
  local resnet50_tpu_vm = experimental.PyTorchTpuVmMixin {
    // This test uses the default pytorch XLA version built into the TPUVM, which
    // is 1.8.1 as of Apr 19.
    frameworkPrefix: 'pt-r1.8.1',
    modelName: 'resnet50-mp',
    paramsOverride: {
      num_epochs: error 'Must set `num_epochs`',
      datadir: error 'Must set `datadir`',
      setup_commands: common.tpu_vm_1_8_1_install,
    },
    command: utils.scriptCommand(
      |||
        %(setup_commands)s
        pip3 install tensorboardX google-cloud-storage
        python3 xla/test/test_train_mp_imagenet.py \
          --logdir=$(MODEL_DIR) \
          --datadir=%(datadir)s \
          --model=resnet50 \
          --num_workers=8 \
          --batch_size=128 \
          --log_steps=200 \
          --num_epochs=%(num_epochs)d \
      ||| % self.paramsOverride,
    ),
    podTemplate+:: {
      spec+: {
        containerMap+: {
          train+: {
            resources+: {
              requests: {
                cpu: '1',
                memory: '2Gi',
              },
            },
          },
        },
      },
    },
  },
  local functional_tpu_vm = common.Functional {
    paramsOverride: {
      num_epochs: 2,
      datadir: '/datasets/imagenet-mini',
      setup_commands: common.tpu_vm_1_8_1_install,
    },
  },
  local convergence_tpu_vm = common.Convergence {
    paramsOverride: {
      num_epochs: 5,
      datadir: '/datasets/imagenet',
      setup_commands: common.tpu_vm_1_8_1_install,
    },
    metricConfig+: {
      sourceMap+:: {
        tensorboard+: {
          aggregateAssertionsMap+:: {
            'Accuracy/test': {
              FINAL: {
                fixed_value: {
                  comparison: 'GREATER',
                  value: 30.0,
                },
                inclusive_bounds: false,
                wait_for_n_data_points: 0,
              },
            },
          },
        },
      },
    },
  },
  local resnet50_tpu_vm_pod = experimental.PyTorchTpuVmPodTest {
    // This test uses the default pytorch XLA version built into the TPUVM, which
    // is 1.8.1 as of Apr 19.
    frameworkPrefix: 'pt-r1.8.1',
    modelName: 'resnet50-mp',
    command: utils.scriptCommand(
      |||
        sudo ls -l /datasets
        sudo ls -l /datasets/imagenet-mini
        python3 -m torch_xla.distributed.xla_dist --tpu=$(cat ~/tpu_name) -- python3 /usr/share/xla/test/test_train_mp_imagenet.py --num_epochs=2 --logdir='' --datadir=/datasets/imagenet-mini --model=resnet50 --num_workers=4 --batch_size=128 --log_steps=200
      |||
    ),
  },
  local v3_8 = {
    accelerator: tpus.v3_8,
  },
  local v3_32 = {
    accelerator: tpus.v3_32,
  },
  configs: [
    common.PyTorchTest + resnet50_tpu_vm + v3_8 + functional_tpu_vm + timeouts.Hours(2),
    common.PyTorchTest + resnet50_tpu_vm + v3_8 + convergence_tpu_vm + timeouts.Hours(4),
    common.PyTorchTest + resnet50_tpu_vm_pod + v3_32 + common.Functional + timeouts.Hours(4),
  ],
}

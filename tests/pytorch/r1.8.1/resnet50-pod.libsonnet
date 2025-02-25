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

local common = import 'common.libsonnet';
local mixins = import 'templates/mixins.libsonnet';
local timeouts = import 'templates/timeouts.libsonnet';
local tpus = import 'templates/tpus.libsonnet';

{
  local resnet50_pod = common.PyTorchGkePodTest {
    modelName: 'resnet50-mp',
    command: [
      'python3',
      '/pytorch/xla/test/test_train_mp_imagenet.py',
    ],
  },
  local resnet50_pod_func = common.PyTorchXlaDistPodTest {
    modelName: 'resnet50-pod',
    condaEnv: 'torch-xla-1.8.1',
    command: [
      'python3',
      '/usr/share/torch-xla-1.8.1/pytorch/xla/test/test_train_mp_imagenet.py',
    ],
  },
  local functional = common.Functional {
    command+: [
      '--fake_data',
      '--num_epochs=5',
    ],

    workerCpu: '8',
    workerMemory: '16Gi',
  },
  local convergence = common.Convergence {
    command+: [
      '--num_epochs=90',
      '--datadir=/datasets/imagenet',
      '--batch_size=128',
      '--log_steps=200',
    ],

    workerCpu: '36',
    workerMemory: '100Gi',
    workerVolumes: {
      datasets: common.datasetsVolume,
    },

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
  local v3_8 = {
    accelerator: tpus.v3_8,
  },
  local v3_32 = {
    accelerator: tpus.v3_32,
  },
  configs: [
    resnet50_pod_func + v3_32 + functional,
    resnet50_pod + v3_32 + convergence,
  ],
}

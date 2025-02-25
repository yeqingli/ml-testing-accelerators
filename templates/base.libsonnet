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

local volumes = import 'volumes.libsonnet';

{
  BaseTest:: {
    local config = self,
    local gcsSubdir = '%(frameworkPrefix)s/%(modelName)s/%(mode)s/%(acceleratorName)s' % config,

    frameworkPrefix: error 'Must specify `frameworkPrefix`',
    modelName: error 'Must specify `modelName`',
    accelerator: error 'Must specify `accelerator`',
    // HACK: for format strings
    acceleratorName:: config.accelerator.name,
    mode: error 'Must set `mode`',
    command: error 'Must specify model `command`',

    // Image in main `train` container.
    image: error 'Must specify mode `image`',
    imageTag: 'latest',

    // Timeout deadline for test, in seconds.
    timeout: error 'Must specify `timeout`',
    // Schedule for CronJob in UTC
    schedule: error 'Must specify `schedule`',

    // Setting for TPU tests -- these can be ignored for GPU tests.
    tpuSettings: {
      // TPU software version (e.g. `nightly`)
      softwareVersion: error 'Must set TPU `softwareVersion`',

      // Require nodes to have label `tpu-available: true`.
      // Useful for regional clusters where not all zones have TPU availabiltiy.
      requireTpuAvailableLabel: false,

      // Whether to use a preemptible TPU.
      preemptible: false,

      // Whether to use a TPU reservation.
      reserved: 'false',
    },

    // CPU/memory resource requests for the `train` container.
    // If null, defer to namespace default.
    cpu: null,
    memory: null,
    // Map of names to VolumeSpecs.
    volumeMap: {},
    // List of ConfigMaps to pull environment variables from.
    configMaps: ['gcs-buckets'],

    // Settings for metric collection and assertions. Should evaluate to
    // MetricCollectionConfig from metrics/metrics.proto. See
    // metrics.MetricCollectionConfigHelper
    metricConfig: null,

    // Kubernetes Pods have a character limit. Ensure that jobs generated from
    // CronJobs are short enough.
    local fullTestName =
      '%(frameworkPrefix)s-%(modelName)s-%(mode)s-%(acceleratorName)s' % config,
    local fullTestNameLen = std.length(fullTestName),
    testName: if fullTestNameLen <= 46 then
      fullTestName
    else
      error 'Test name %s has %d characters. The limit is 46 characters.' %
            [fullTestName, fullTestNameLen],

    labels: {
      benchmarkId: config.testName,
      frameworkVersion: config.frameworkPrefix,
      model: config.modelName,
      mode: config.mode,
      accelerator: config.accelerator.name,
    },

    podTemplate:: config.accelerator.PodTemplate(config.tpuSettings) {
      spec+: volumes.combinedMixin(config.volumeMap) + {
        local pod = self,
        local commonEnv = [
          {
            name: 'POD_NAME',
            valueFrom: {
              fieldRef: {
                fieldPath: 'metadata.name',
              },
            },
          },
          {
            name: 'POD_UID',
            valueFrom: {
              fieldRef: {
                fieldPath: 'metadata.uid',
              },
            },
          },
          {
            name: 'POD_NAMESPACE',
            valueFrom: {
              fieldRef: {
                fieldPath: 'metadata.namespace',
              },
            },
          },
          {
            name: 'JOB_NAME',
            valueFrom: {
              fieldRef: {
                fieldPath: "metadata.labels['job-name']",
              },
            },
          },
          {
            name: 'MODEL_DIR',
            value: '$(OUTPUT_BUCKET)/%s/$(JOB_NAME)' % gcsSubdir,
          },
        ],

        restartPolicy: 'Never',
        initContainerMap:: {},
        initContainers: [
          { name: name } + pod.initContainerMap[name]
          for name in std.objectFields(pod.initContainerMap)
        ],

        containerMap+:: {
          train+: {
            local main = self,

            image: '%(image)s:%(imageTag)s' % config,
            imagePullPolicy: 'Always',
            // Use Docker image's entrypoint wrapper
            args: config.command,

            envFrom: [
              {
                configMapRef: {
                  name: bucketName,
                },
              }
              for bucketName in config.configMaps
            ],

            // Override this object to add environment variables to the container
            envMap:: {},
            env: commonEnv + [
              {
                name: key,
                value: main.envMap[key],
              }
              for key in std.objectFields(main.envMap)
            ],

            resources+: std.prune({
              requests+: {
                cpu: config.cpu,
                memory: config.memory,
              },
            }),
          },
        },
        containers: [
          { name: name } + pod.containerMap[name]
          for name in std.objectFields(pod.containerMap)
          if pod.containerMap[name] != null
        ],
      },
    },

    runnablePod:: config.podTemplate {
      apiVersion: 'v1',
      kind: 'Pod',
      metadata+: {
        generateName: '%s-' % config.testName,
      },

      // HACK: Use pod name as $JOB_NAME, since this pod is not in a Job.
      spec+: {
        containerMap+: {
          train+: {
            env: [
              if e.name == 'JOB_NAME' then
                e { valueFrom: { fieldRef: { fieldPath: 'metadata.name' } } }
              else
                e
              for e in super.env
            ],
          },
        },
      },
    },

    jobTemplate+:: {
      metadata: {
        annotations+: if config.metricConfig != null then {
          'ml-testing-accelerators/metric-config':
            std.manifestJsonEx(config.metricConfig, '  ') + '\n',
          'ml-testing-accelerators/gcs-subdir': gcsSubdir,
        } else {},
        labels: config.labels,
      },
      spec: {
        // Try 2 times before giving up.
        backoffLimit: 1,
        activeDeadlineSeconds: config.timeout,
        template: config.podTemplate,
      },
    },

    oneshotJob:: {
      local oneshotConfig = config {
        // Don't publish PubSub message for oneshot jobs.
        publisherImage: null,

        jobTemplate+:: {
          spec+: {
            // Don't retry oneshot jobs.
            backoffLimit: 0,
          },
        },
      },

      apiVersion: 'batch/v1',
      kind: 'Job',
      metadata: oneshotConfig.jobTemplate.metadata {
        generateName: '%s-' % oneshotConfig.testName,
      },
      spec: oneshotConfig.jobTemplate.spec,
    },

    cronJob:: {
      apiVersion: 'batch/v1beta1',
      kind: 'CronJob',
      metadata: {
        name: config.testName,
        labels: config.labels,
      },
      spec: {
        schedule: config.schedule,
        concurrencyPolicy: 'Forbid',
        successfulJobsHistoryLimit: 1,
        jobTemplate: config.jobTemplate,
      },
    },
  },

  BaseAccelerator:: {
    name: error 'Must define accelerator `name`',
    type: error 'Must define accelerator `type`',
    replicas: error 'Must define accelerator `replicas`',

    // tpuSettings should be ignored.
    PodTemplate(tpuSettings):: error 'Must define accelerator `PodSpec`.',
  },
  cpu:: self.BaseAccelerator {
    name: 'cpu',
    type: 'cpu',
    replicas: 1,

    // Ignore TPU settings.
    PodTemplate(_):: {
      spec+: {
        containerMap+: {
          train+: {
            resources+: {
              limits+: {
                cpu: 2,
                memory: '2Gi',
              },
            },
          },
        },
      },
    },
  },
}

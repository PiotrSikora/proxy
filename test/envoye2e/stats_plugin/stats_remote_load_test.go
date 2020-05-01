// Copyright 2019 Istio Authors
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

package client

import (
	"testing"
	"time"

	"istio.io/proxy/test/envoye2e"
	"istio.io/proxy/test/envoye2e/driver"
)

const StatsRLServerHTTPListener = `
name: server
traffic_direction: INBOUND
address:
  socket_address:
    address: 127.0.0.1
    port_value: {{ .Ports.ServerPort }}
filter_chains:
- filters:
  - name: http
    typed_config:
      "@type": type.googleapis.com/envoy.extensions.filters.network.http_connection_manager.v3.HttpConnectionManager
      codec_type: AUTO
      stat_prefix: server
      http_filters:
      - name: envoy.filters.http.wasm
        typed_config:
          "@type": type.googleapis.com/udpa.type.v1.TypedStruct
          type_url: envoy.extensions.filters.http.wasm.v3.Wasm
          value:
            config:
              root_id: "stats_inbound"
              vm_config:
                vm_id: stats_inbound
                runtime: envoy.wasm.runtime.v8
                code:
                  remote:
                    http_uri:
                      uri: http://storage.googleapis.com/istio-build/proxy/stats-d1dd3cef40fd1e78d7840a6d58f2c351cbc8add4.wasm
                      cluster: storage.googleapis.com
                      timeout: 10s
                    sha256: d2b63d70af78690e377bc9989ace94ad8889ef45c2307f605c9e149c226a3535
              configuration: |
                {{ .Vars.StatsFilterServerConfig }}
      - name: envoy.filters.http.router
      route_config:
        name: server
        virtual_hosts:
        - name: server
          domains: ["*"]
          routes:
          - match: { prefix: / }
            route:
              cluster: inbound|9080|http|server.default.svc.cluster.local
              timeout: 0s`

const StorageCluster = `- name: storage.googleapis.com
  connect_timeout: 10s
  type: STRICT_DNS
  dns_refresh_rate: 5s
  load_assignment:
    cluster_name: storage.googleapis.com
    endpoints:
    - lb_endpoints:
      - endpoint:
          address:
            socket_address:
              address: storage.googleapis.com
              port_value: 80`

func TestStatsRemoteLoad(t *testing.T) {
	params := driver.NewTestParams(t, map[string]string{
		"ServerStaticCluster":     StorageCluster,
		"StatsConfig":             driver.LoadTestData("testdata/bootstrap/stats.yaml.tmpl"),
		"StatsFilterServerConfig": driver.LoadTestJSON("testdata/stats/server_config.yaml"),
	}, envoye2e.ProxyE2ETests)
	params.Vars["ServerMetadata"] = params.LoadTestData("testdata/server_node_metadata.json.tmpl")

	if err := (&driver.Scenario{
		Steps: []driver.Step{
			&driver.XDS{},
			&driver.Update{Node: "server", Version: "0", Listeners: []string{StatsRLServerHTTPListener}},
			&driver.Envoy{Bootstrap: params.LoadTestData("testdata/bootstrap/server.yaml.tmpl")},
			&driver.Sleep{Duration: 10 * time.Second},
			&driver.Repeat{N: 10,
				Step: &driver.HTTPCall{
					Port: params.Ports.ServerPort,
					Body: "hello, world!",
				},
			},
		},
	}).Run(params); err != nil {
		t.Fatal(err)
	}
}

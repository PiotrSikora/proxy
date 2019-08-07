#!/bin/bash
#
# Copyright 2016 Istio Authors. All Rights Reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
################################################################################
#
set -ex

# Use clang for the release builds.
export PATH=/usr/lib/llvm-8/bin:$PATH
export CC=${CC:-clang}
export CXX=${CXX:-clang++}

# The bucket name to store proxy binary
DST="gs://istio-build/proxy"

function usage() {
  echo "$0
    -d  The bucket name to store proxy binary (optional)"
  exit 1
}

while getopts d: arg ; do
  case "${arg}" in
    d) DST="${OPTARG}";;
    *) usage;;
  esac
done

echo "Destination bucket: $DST"

# The bucket name to store proxy binary
# DST="gs://istio-build/proxy"

# Make sure to this script on x86_64 Ubuntu Xenial
UBUNTU_RELEASE=${UBUNTU_RELEASE:-$(lsb_release -c -s)}
[[ "${UBUNTU_RELEASE}" == 'xenial' ]] || { echo 'must run on Ubuntu Xenial'; exit 1; }

# Symlinks don't work, use full path as a temporary workaround.
# See: https://github.com/istio/istio/issues/15714 for details.
# k8-opt is the output directory for x86_64 optimized builds (-c opt, so --config=release-symbol and --config=release).
BAZEL_OUT="$(bazel info output_path)/k8-opt/bin"

# The proxy binary name.
SHA="$(git rev-parse --verify HEAD)"

BINARY_NAME="${HOME}/envoy-symbol-${SHA}.tar.gz"
SHA256_NAME="${HOME}/envoy-symbol-${SHA}.sha256"

# If binary already exists skip.
gsutil stat "${DST}/${BINARY_NAME}" \
  && { echo 'Binary already exists'; exit 0; } \
  || echo 'Building a new binary.'

# Build the release binary with symbols.
bazel build ${BAZEL_BUILD_ARGS} --config=release-symbol //src/envoy:envoy_tar
BAZEL_TARGET="${BAZEL_OUT}/src/envoy/envoy_tar.tar.gz"
cp -f "${BAZEL_TARGET}" "${BINARY_NAME}"
sha256sum "${BINARY_NAME}" > "${SHA256_NAME}"

# Copy it to the bucket.
echo "Copying ${BINARY_NAME} ${SHA256_NAME} to ${DST}/"
gsutil cp "${BINARY_NAME}" "${SHA256_NAME}" "${DST}/"

# Build the release binary.
BINARY_NAME="${HOME}/envoy-alpha-${SHA}.tar.gz"
SHA256_NAME="${HOME}/envoy-alpha-${SHA}.sha256"
bazel build ${BAZEL_BUILD_ARGS} --config=release //src/envoy:envoy_tar
BAZEL_TARGET="${BAZEL_OUT}/src/envoy/envoy_tar.tar.gz"
cp -f "${BAZEL_TARGET}" "${BINARY_NAME}"
sha256sum "${BINARY_NAME}" > "${SHA256_NAME}"

# Copy it to the bucket.
echo "Copying ${BINARY_NAME} ${SHA256_NAME} to ${DST}/"
gsutil cp "${BINARY_NAME}" "${SHA256_NAME}" "${DST}/"

# Build the release package.
BINARY_NAME="${HOME}/istio-proxy-${SHA}.deb"
SHA256_NAME="${HOME}/istio-proxy-${SHA}.sha256"
bazel build ${BAZEL_BUILD_ARGS} --config=release //tools/deb:istio-proxy
BAZEL_TARGET="${BAZEL_OUT}/tools/deb/istio-proxy.deb"
cp -f "${BAZEL_TARGET}" "${BINARY_NAME}"
sha256sum "${BINARY_NAME}" > "${SHA256_NAME}"

# Copy it to the bucket.
echo "Copying ${BINARY_NAME} ${SHA256_NAME} to ${DST}/"
gsutil cp "${BINARY_NAME}" "${SHA256_NAME}" "${DST}/"

# Symlinks don't work, use full path as a temporary workaround.
# See: https://github.com/istio/istio/issues/15714 for details.
# k8-dbg is the output directory for x86_64 debug builds (-c dbg).
BAZEL_OUT="$(bazel info output_path)/k8-dbg/bin"

# Build the debug binary.
BINARY_NAME="${HOME}/envoy-debug-${SHA}.tar.gz"
SHA256_NAME="${HOME}/envoy-debug-${SHA}.sha256"
bazel build ${BAZEL_BUILD_ARGS} -c dbg //src/envoy:envoy_tar
BAZEL_TARGET="${BAZEL_OUT}/src/envoy/envoy_tar.tar.gz"
cp -f "${BAZEL_TARGET}" "${BINARY_NAME}"
sha256sum "${BINARY_NAME}" > "${SHA256_NAME}"

# Copy it to the bucket.
echo "Copying ${BINARY_NAME} ${SHA256_NAME} to ${DST}/"
gsutil cp "${BINARY_NAME}" "${SHA256_NAME}" "${DST}/"

# Build the debug package.
BINARY_NAME="${HOME}/istio-proxy-debug-${SHA}.deb"
SHA256_NAME="${HOME}/istio-proxy-debug-${SHA}.sha256"
bazel build ${BAZEL_BUILD_ARGS} -c dbg //tools/deb:istio-proxy
BAZEL_TARGET="${BAZEL_OUT}/tools/deb/istio-proxy.deb"
cp -f "${BAZEL_TARGET}" "${BINARY_NAME}"
exit
sha256sum "${BINARY_NAME}" > "${SHA256_NAME}"

# Copy it to the bucket.
echo "Copying ${BINARY_NAME} ${SHA256_NAME} to ${DST}/"
gsutil cp "${BINARY_NAME}" "${SHA256_NAME}" "${DST}/"

bazel shutdown

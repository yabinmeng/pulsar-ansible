#! /bin/bash

###
# Copyright DataStax, Inc.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
# http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
###

SCRIPT_FOLDER=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
ANS_SCRIPT_HOMEDIR=$( cd -- "${SCRIPT_FOLDER}/../../../../" &> /dev/null && pwd )
JWT_STAGAING_DIR="${ANS_SCRIPT_HOMEDIR}/staging/security/authentication/jwt"

echo

usage() {
   echo "Usage: cleanupUserJwtToken.sh [-h] -clstr <cluster_name> -host_type <srv_host_type> "
   echo "       -h : show usage info"
   echo "       -clst_name <cluster_name> : Pulsar cluster name" 
   echo "       -host_type <srv_host_type> : Pulsar server host type that needs to clean up JWT tokens (e.g. broker, functions_worker)"
}

srvHostType=""
while [[ "$#" -gt 0 ]]; do
   case $1 in
      -h) usage; echo; exit 10 ;;
      -clst_name) pulsarClusterName="$2"; shift;;
      -host_type) srvHostType="$2"; shift ;;
      *) echo "Unknown parameter passed: $1"; echo; exit 20 ;;
   esac
   shift
done

if [[ -z "${pulsarClusterName// }" ]]; then
  echo "Pulsar cluster name can't be empty" 
  echo
  exit 30
fi

if [[ -z "${srvHostType// }" ]]; then
  echo "[ERROR] Pulsar server host type can't be empty" 
  echo
  exit 40
fi

rm -rf ${JWT_STAGAING_DIR}/token/${pulsarClusterName}/${srvHostType}s/*
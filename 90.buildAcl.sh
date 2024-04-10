#! /usr/local/bin/bash

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

###
# NOTE 1: the default MacOS /bin/bash version is 3.x and doesn't have the feature of 
#         associative arrary. Homebrew installed bash is under "/usr/local/bin/bash"
#
# Change to default "/bin/bash" if your system has the right version (4.x and above)
#

# This script is used for generating the Ansible host inventory file from
#   the cluster topology raw definition file
# 
#   this script only works for bash 4 and above
#   * by default, MacOs bash version is 3.x (/bin/bash)
#   * use custom-installed bash using homebrew (/usar/local/bin/bash) at version 5.x
#

SCRIPT_FOLDER=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
ANS_SCRIPT_HOMEDIR=$( cd -- "${SCRIPT_FOLDER}/" &> /dev/null && pwd )

echo

DEBUG=false

bashVerCmdOut=$(bash --version)
re='[0-9].[0-9].[0-9]'
bashVersion=$(echo ${bashVerCmdOut} | grep -o "version ${re}" | grep -o "${re}")
bashVerMajor=$(echo ${bashVersion} | awk -F'.' '{print $1}' )

if [[ ${bashVerMajor} -lt 4 ]]; then
  echo "[ERROR] Unspported bash version (${bashVersion}). Must be version 4.x and above!";
	echo
  exit 1
fi

# only 1 parameter: the message to print for debug purpose
debugMsg() {
	if [[ "${DEBUG}" == "true" ]]; then
		if [[ $# -eq 0 ]]; then
			echo
		else
			echo "[Debug] $1"
		fi
	fi
}

aclRawDefHomeDir="${ANS_SCRIPT_HOMEDIR}/permission_matrix"

validAclOpTypeArr=("grant" "revoke")
validAclOpTypeListStr="${validAclOpTypeArr[@]}"
debugMsg "validAclOpTypeListStr=${validAclOpTypeListStr}"

validResourceTypeArr=("topic" "namespace" "ns-subscription" "tp-subscription")
validResourceTypeListStr="${validResourceTypeArr[@]}"
debugMsg "validResourceTypeListStr=${validResourceTypeListStr}"

validAclActionArr=("produce" "consume" "sources" "sinks" "functions" "packages")
validAclActionListStr="${validAclActionArr[@]}"
debugMsg "validAclActionListStr=${validAclActionListStr}"

usage() {
  echo "Usage: buildAnsiHostInvFile.sh [-h]"
  echo "                                -clstrName <cluster_name>"
  echo "                                -aclDef <acl_definition_file>"
  echo "                               [-skipRoleJwt] <skip_role_jwt_generation>"
  echo "                               [-ansiPrivKey <ansi_private_key>"
  echo "                               [-ansiSshUser <ansi_ssh_user>"
  echo "       -h : Show usage info"
  echo "       -clstrName : Pulsar cluster name"
  echo "       -aclDef : Pulsar ACL definition file"
  echo "       [-skipRoleJwt] : Whether to skip JWT token generation for the specified roles"
  echo "       [-ansiPrivKey] : The private SSH key file used to connect to Ansible hosts"
  echo "       [-ansiSshUser] : The SSH user used to connect to Ansible hosts"
}

if [[ $# -eq 0 || $# -gt 10 ]]; then
  usage
	echo
  exit 10
fi

while [[ "$#" -gt 0 ]]; do
	case $1 in
		-h) usage; echo; exit 0 ;;
		-clstrName) clstrName=$2; shift ;;
		-aclDef) aclDefFileName=$2; shift ;;
		-skipRoleJwt) skipRoleJwt=$(echo $2 | tr '[:upper:]' '[:lower:]'); shift ;;
		-ansiPrivKey) ansiPrivKey=$2; shift ;;
		-ansiSshUser) ansiSshUser=$2; shift ;;
		*) echo "[ERROR] Unknown parameter passed: $1"; echo; exit 20 ;;
	esac
	shift
done

ANSI_HOSTINV_FILE="hosts_${clstrName}.ini"

aclDefExecLogHomeDir="${aclRawDefHomeDir}/${clstrName}/logs"
mkdir -p "${aclDefExecLogHomeDir}/acl_perm_exec_log"

aclDefFilePath="${aclRawDefHomeDir}/${clstrName}/${aclDefFileName}"

if [[ -z "${ansiPrivKey// }" ]]; then
  ansiPrivKey=${ANSI_SSH_PRIV_KEY}
fi
if [[ -z "${ansiSshUser// }" ]]; then
  ansiSshUser=${ANSI_SSH_USER}
fi

if [[ -z "${ansiPrivKey// }" || -z "${ansiSshUser// }" ]]; then
  echo "[ERROR] Missing mandatory SSH key and user name which can be either explicitly provided via '-ansiPrivKey' and '-ansiSshUser' or set in `setenv_automation.sh` file!"
	echo
  exit 25
fi

debugMsg "aclDefFilePath=${aclDefFilePath}"
debugMsg "ansiPrivKey=${ansiPrivKey}"
debugMsg "ansiSshUser=${ansiSshUser}"

# Check if the corrsponding Pulsar cluster definition file exists
if ! [[ -f "${aclDefFilePath}" ]]; then
  echo "[ERROR] Can't find the specified ACL raw definition file of the specific Pulsar cluster: ${aclDefFilePath}";
	echo
  exit 30
fi

re='(true|false)'
if [[ -z "${skipRoleJwt// }" ]]; then
    skipRoleJwt="false"
fi
if ! [[ ${skipRoleJwt} =~ $re ]]; then
	echo "[ERROR] Invalid value for the following input parameter of '-skipRoleJwt'. Value 'true' or 'false' is expected." 
	echo
	exit 40
fi


##
# Check if an element is contained in an arrary
# - 1st parameter: the element to match
# - 2nd parameter: the array 
containsElementInArr () {
	local e match="$1"
	shift
	for e; do [[ "$e" == "$match" ]] && return 0; done
	return 1
}

stepCnt=0

stepCnt=$((stepCnt+1))
echo "${stepCnt}. Process the specified raw ACL definition file for validity check: ${aclDefFilePath} ..."

roleNameArr=()
uniqueRoleNameArr=()
aclOpArr=()
resourceTypeArr=()
resourceNameArr=()
aclActionListStrArr=()

while read LINE || [ -n "${LINE}" ]; do
	# Ignore comments
	case "${LINE}" in \#*) continue ;; esac
	IFS=',' read -r -a FIELDS <<< "${LINE#/}"

	roleName=${FIELDS[0]}
	aclOp=${FIELDS[1]}
	resourceType=${FIELDS[2]}
	resourceName=${FIELDS[3]}
	aclActionListStr=${FIELDS[4]}

	debugMsg "roleName=${roleName}"
	debugMsg "aclOp=$(echo ${aclOp} | tr '[:upper:]' '[:lower:]')"
	debugMsg "resourceType=$(echo ${resourceType} | tr '[:upper:]' '[:lower:]')"
	debugMsg "resourceName=${resourceName}"
	debugMsg "aclActionListStr=$(echo ${aclActionListStr} | tr '[:upper:]' '[:lower:]')"
	
	# General validity test
	if [[ -z "${roleName// }"||  -z "${aclOp// }" || -z "${resourceType// }" || -z "${resourceName// }" ]]; then
		echo "[ERROR] Invalid ACL defintion line: \"${LINE}\". All fields (except 'aclOption') must not be empty!" 
		echo
		exit 50
	elif ! [[ "${validAclOpTypeListStr}" =~ "${aclOp}" ]]; then 
		echo "[ERROR] Invalid ACL operation type '${aclOp}' on line \"${LINE}\". Valid types: ${validAclOpTypeListStr}" 
		echo
		exit 60
	elif ! [[ "${validResourceTypeListStr}" =~ "${resourceType}" ]]; then 
		echo "[ERROR] Invalid ACL resouce type '${resourceType}' on line \"${LINE}\". Valid types: ${validResourceTypeListStr}" 
		echo
		exit 70
	else
		IFS='+' read -r -a aclLineActionArr <<< "${aclActionListStr}"
		for aclAction in ${aclLineActionArr[@]} ; do
			if ! [[ "${validAclActionListStr}" =~ "${aclAction}" ]]; then 
				echo "[ERROR] Invalid ACL action type '${aclAction}' on line \"${LINE}\". Valid types: ${validAclActionListStr}" 
				echo
				exit 80
			fi
		done
	fi

	# Resource type specific validity check
	tp_re="^(persistent|non-persistent)://[[:alnum:]_.-]+/[[:alnum:]_.-]+/[[:alnum:]_.-]+$"
	ns_re="^[[:alnum:]_.-]+/[[:alnum:]_.-]+$"
	ns_sb_re="^[[:alnum:]_.-]+/[[:alnum:]_.-]+:[[:alnum:]_.-]+$"
	if [[ "${resourceType}" == "topic" ]]; then
		if ! [[ "${resourceName}" =~ ${tp_re} ]]; then
			echo "[ERROR] Invalid resource name pattern ('${resourceName}') for the specified resource type '${resourceType}' on line \"${LINE}\". Expecting name pattern: \"${tp_re}\"!" 
			echo
			exit 90
		fi
	elif [[ "${resourceType}" == "namespace" ]]; then
		if ! [[ "${resourceName}" =~ ${ns_re} ]]; then
			echo "[ERROR] Invalid resource name pattern ('${resourceName}') for the specified resource type '${resourceType}' on line \"${LINE}\". Expecting name pattern: \"${ns_re}\"!" 
			echo
			exit 100
		fi
	elif [[ "${resourceType}" == "ns-subscription" ]]; then
		if ! [[ "${resourceName}" =~ ${ns_sb_re} ]]; then
			echo "[ERROR] Invalid resource name pattern ('${resourceName}') for the specified resource type '${resourceType}' on line \"${LINE}\". Expecting name pattern: \"${ns_sb_re}\"!" 
			echo
			exit 110
		fi
	fi

	# aclActionListStr can be empty for 'subscription' resource 
	if [[ -z "${aclActionListStr// }" ]]; then
		aclActionListStr="n/a"
	fi

	roleNameArr+=("${roleName}")
	containsElementInArr "${roleName}" "${uniqueRoleNameArr[@]}"
	if [[ $? -eq 1 ]]; then
		uniqueRoleNameArr+=("${roleName}")
	fi

	aclOpArr+=("${aclOp}")
	resourceTypeArr+=("${resourceType}")
	aclActionListStrArr+=("${aclActionListStr}")
	resourceNameArr+=("${resourceName}")

done < ${aclDefFilePath}

roleNameList="${roleNameArr[@]}"
uniqueRoleNameList="${uniqueRoleNameArr[@]}"
aclOpList="${aclOpArr[@]}"
resourceTypeList="${resourceTypeArr[@]}"
aclActionListStrList="${aclActionListStrArr[@]}"
debugMsg "roleNameList=${roleNameList}"
debugMsg "uniqueRoleNameList=${uniqueRoleNameList}"
debugMsg "aclOpList=${aclOpList}"
debugMsg "resourceTypeList=${resourceTypeList}"
debugMsg "aclActionListStrArr=${aclActionListStrList}"
echo "   done!"

if [[ "${skipRoleJwt}" == "false" ]]; then
    echo
    stepCnt=$((stepCnt+1))
    
    ansiPlaybookName="01.create_secFiles.yaml"
    ANSI_HOSTINV_FILE="hosts_${clstrName}.ini"
    ansiTcExecLog="${aclDefExecLogHomeDir}/${aclDefFileName}-create_secFiles.yaml.log"
    
    echo "${stepCnt}. Call Ansible script to create JWT tokens for all roles specified in the ACL raw definition file"
    echo "   execution log file: ${ansiTcExecLog}"
    ansible-playbook -i ${ANSI_HOSTINV_FILE} ${ansiPlaybookName} \
			--extra-vars="cleanLocalSecStaging=false user_roles_list=${uniqueRoleNameList// /,} jwtTokenOnly=true brokerOnly=true" \
			--private-key=${ansiPrivKey} \
			-u ${ansiSshUser} -v > ${ansiTcExecLog} 2>&1

    if [[ $? -ne 0 ]]; then
			echo "   [ERROR] Failed to create specifie JWT tokens for the specified roles!" 
			echo
			exit 120
    else
			echo "   done!"
    fi
    echo
fi

echo
stepCnt=$((stepCnt+1))
echo "${stepCnt}. Generate pulsar-amdin command template file to grant/revoke permissions according to the ACL definition."

pulsarCliAclExecTemplFile="${aclRawDefHomeDir}/${clstrName}/${aclDefFileName}_pulsarCliCmdTmpl"
echo "#! /bin/bsh" > ${pulsarCliAclExecTemplFile}
echo >> ${pulsarCliAclExecTemplFile}
echo "aclIndex=0" >> ${pulsarCliAclExecTemplFile}
echo >> ${pulsarCliAclExecTemplFile}

for index in "${!roleNameArr[@]}"; do
	roleName=${roleNameArr[$index]}
	aclOp=${aclOpArr[$index]}
	resourceType=${resourceTypeArr[$index]}
	resourceName=${resourceNameArr[$index]}

	# convert to the format recogonized by pulsar-admin command
	aclActionListStr=$(echo ${aclActionListStrArr[$index]} | tr '+' ',' )

	if [[ "${resourceType}" == "namespace" ]]; then
		adminCmd="namespaces"
		adminSubCmd="${aclOp}-permission"
	elif [[ "${resourceType}" == "topic" ]]; then
		adminCmd="topics"
		adminSubCmd="${aclOp}-permission"
	elif [[ "${resourceType}" == "ns-subscription" ]]; then
		adminCmd="namespaces"
		adminSubCmd="${aclOp}-subscription-permission"
	#
	## future work: topic subscription
	#
	# elif [[ "${resourceType}" == "ns-subscription" ]]; then
	#     adminCmd="namespaces"
	#     adminSubCmd="${aclOp}-subscription-permission"
	fi

	pulsarAdminCmdStrToExec="<PULSAR_ADMIN_CMD> ${adminCmd} ${adminSubCmd}"

	if [[ "${resourceType}" == "ns-subscription" ]]; then
		# for "ns-subscription", the resource name is in format "<tenant>/<namespace>:<subscription>"
		IFS=':' read -r -a nsSubArr <<< "${resourceName}"
		pulsarAdminCmdStrToExec="${pulsarAdminCmdStrToExec} ${nsSubArr[0]} --subscription ${nsSubArr[1]} --roles ${roleName}"
	#
	## future work: topic subscription
	#
	# elif [[ "${resourceType}" == "ns-subscription" ]]; then
	#     pulsarAdminCmdStrToExec="TBD ..."
	else
		pulsarAdminCmdStrToExec="${pulsarAdminCmdStrToExec} ${resourceName} --role ${roleName}"
		if [[ "${aclOp}" == "grant" ]]; then
				pulsarAdminCmdStrToExec="${pulsarAdminCmdStrToExec} --actions ${aclActionListStr}"
		fi
	fi

	echo 'aclIndex=$((aclIndex+1))' >> ${pulsarCliAclExecTemplFile}
	echo "${pulsarAdminCmdStrToExec}" >> ${pulsarCliAclExecTemplFile}
	echo 'if [[ $? -ne 0 ]]; then' >> ${pulsarCliAclExecTemplFile}
	echo '    exit ${aclIndex}' >> ${pulsarCliAclExecTemplFile}
	echo 'fi' >> ${pulsarCliAclExecTemplFile}
	echo >> ${pulsarCliAclExecTemplFile}  
done
echo 'exit 0' >> ${pulsarCliAclExecTemplFile}
echo "   done!"

echo
stepCnt=$((stepCnt+1))

ansiPlaybookName="exec_AclPermControl.yaml"
ansiTcExecLog="${aclDefExecLogHomeDir}/${aclDefFileName}-exec_AclPermControl.yaml.log"

echo "${stepCnt}. Call Ansible script to execute Pulsar ACL permission management commands"
echo "   execution log file: ${ansiTcExecLog}"
ansible-playbook -i ${ANSI_HOSTINV_FILE} ${ansiPlaybookName} \
	--extra-vars="aclDefRawName=${aclDefFileName}" \
	--private-key=${ansiPrivKey} \
	-u ${ansiSshUser} -v > ${ansiTcExecLog} 2>&1

if [[ $? -ne 0 ]]; then
	echo "   [ERROR] Not all Pulsar ACL permission management commands are executed successfully! Please check the remote execute log!" 
	echo
	exit 120
else
	echo "   done!"
fi
echo

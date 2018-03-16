#######################################################
# Project: K8s/Cluster-configuration-verification
# Script:  Verify all nodes have appropriate bootstrap configurations.
# Author:  Neeraj Sharma
# Date:    12/19/2017
#######################################################

declare -a success
s_index=0

declare -a failues
f_index=0

declare -a backend_nodes
b_index=0

declare -a ipvs_nodes
i_index=0

declare -a infra_nodes
infra_index=0

check_lo_vip_on_backend_nodes()
{
	for node in ${backend_nodes[*]};
	do
		sub_if=`ssh -l root $node -i $dplyr_identity "ip a sh dev lo | grep lo:1" 2> /dev/null`
		if [[ "$sub_if" =~ "/32 brd " ]]; then
			success[$s_index]="lo:1 vip: $node is OK."
			((s_index++))
		else 
			failures[$f_index]="lo:1 vip: $node is missing vip."
			((f_index++))
		fi
	done
}

check_sysctl_info_for_backend_nodes()
{
for node in ${backend_nodes[*]};
do
	lines=(`ssh -l root $node -i $dplyr_identity "cat /etc/sysctl.conf" 2> /dev/null `)
	ip_forward=0
	arp_ignore=0
	arp_announce=0
	all_arp_ignore=0
	all_arp_announce=0
	for aline in ${lines[*]};
	do
		if [[ "$aline" =~ "net.ipv4.ip_forward=1" ]]; then
			ip_forward=1
		fi
		if [[ "$aline" =~ "net.ipv4.conf.lo.arp_ignore=1" ]]; then
			arp_ignore=1
		fi
		if [[ "$aline" =~ "net.ipv4.conf.lo.arp_announce=2" ]]; then
			arp_announce=1
		fi
		if [[ "$aline" =~ "net.ipv4.conf.all.arp_ignore=1" ]]; then
			all_arp_ignore=1
		fi
		if [[ "$aline" =~ "net.ipv4.conf.all.arp_announce=2" ]]; then
			all_arp_announce=1
		fi
	done
		
	if [ "$ip_forward" == "1" -a "$arp_ignore" == "1" -a "$arp_announce" == "1" -a "$all_arp_ignore" == "1" -a "$all_arp_announce" == "1" ]; then
		success[$s_index]="SYSCTL: $node is OK."
		((s_index++))
	else 
		error="SYSCTL:  $node is missing: "
		if [ "$ip_forward" == "0" ]; then
			failures[$f_index]=`echo $error net.ipv4.ip_forward=0` 
			((f_index++))
		fi
		if [ "$arp_ignore" == "0" ]; then
			failures[$f_index]=`echo $error net.ipv4.conf.lo.arp_ignore=0` 
			((f_index++))
		fi
		if [ "$arp_announce" == "0" ]; then
			failures[$f_index]=`echo $error net.ipv4.conf.lo.arp_announce=0` 
			((f_index++))
		fi
		if [ "$all_arp_ignore" == "0" ]; then
			failures[$f_index]=`echo $error net.ipv4.conf.all.arp_ignore=0` 
			((f_index++))
		fi
		if [ "$all_arp_announce" == "0" ]; then
			failures[$f_index]=`echo $error net.ipv4.conf.all.arp_announce=0` 
			((f_index++))
		fi
	fi
done

for node in ${ipvs_nodes[*]};
do
	lines=(`ssh -l root $node -i $dplyr_identity "cat /etc/sysctl.conf" 2> /dev/null `)
	ip_forward=0
	for aline in ${lines[*]};
	do
		if [[ "$aline" =~ "net.ipv4.ip_forward=1" ]]; then
			ip_forward=1
		fi
	done

	if [ "$ip_forward" == "1" ]; then
		success[$s_index]="SYSCTL: $node is OK."
		((s_index++))
	else 
		error="SYSCTL:  $node is missing: "
		if [ "$ip_forward" == "0" ]; then
			failures[$f_index]=`echo $error net.ipv4.ip_forward=0` 
			((f_index++))
		fi
	fi
done
}

check_network_labels_of_backend_nodes()
{
	for node in ${backend_nodes[*]};
	do
		labels=(`oc get node $node --show-labels | grep -v NAME | sed -e "s/,/ /g"`)
		eth1_label_found=0
		lo_label_found=0
		for label in ${labels[*]};
		do
			if [[ "$label" =~ "network.cisco.com/eth1=" ]]; then
				eth1_label_found=1
			fi

			if [[ "$label" =~ "network.cisco.com/lo=127.0.0.1" ]]; then
				lo_label_found=1
			fi
		done

		if [ "$eth1_label_found" == "1" -a "$lo_label_found" == "1" ]; then
			success[$s_index]="Network Labels: $node is OK."
			((s_index++))
		else 
			error="Network Labels:  $node is missing: "
			if [ "$eth1_label_found" == "0" ]; then
				failures[$f_index]=`echo $error network.cisco.com/eth1=` 
				((f_index++))
			fi
			if [ "$lo_label_found" == "0" ]; then
				failures[$f_index]=`echo $error network.cisco.com/lo=` 
				((f_index++))
			fi
		fi
	done
}

check_network_labels_of_ipvs_nodes()
{
	for node in ${ipvs_nodes[*]};
	do
		labels=(`oc get node $node --show-labels | grep -v NAME | sed -e "s/,/ /g"`)
		eth1_label_found=0
		lo_label_found=0
		for label in ${labels[*]};
		do
			if [[ "$label" =~ "network.cisco.com/eth1=" ]]; then
				eth1_label_found=1
			fi

			if [[ "$label" =~ "network.cisco.com/lo=127.0.0.1" ]]; then
				lo_label_found=1
			fi
		done

		if [ "$eth1_label_found" == "1" -a "$lo_label_found" == "1" ]; then
			success[$s_index]="Network Labels: $node is OK."
			((s_index++))
		else 
			error="Network Labels:  $node is missing: "
			if [ "$eth1_label_found" == "0" ]; then
				failures[$f_index]=`echo $error network.cisco.com/eth1=` 
				((f_index++))
			fi
			if [ "$lo_label_found" == "0" ]; then
				failures[$f_index]=`echo $error network.cisco.com/lo=` 
				((f_index++))
			fi
		fi
	done
}

check_ipvs_iptables_reset_connection()
{
	for node in ${ipvs_nodes[*]};
	do
		tcp_rule=`ssh -l root $node -i $dplyr_identity "iptables -L OS_FIREWALL_ALLOW  -n | grep '^ACCEPT' | grep 'tcp dpt:80$'" 2> /dev/null`
		if [[ "$tcp_rule" != "" ]]; then
			rule_ok=`echo $tcp_rule | grep "state NEW"`
			if [[ "$rule_ok" == "" ]]; then
				success[$s_index]="iptables OS_FIREWALL_ALLOW rule: $node is OK."
				((s_index++))
			else 
				failures[$f_index]="iptables OS_FIREWALL_ALLOW rule: $node is not fixed."
				((f_index++))
			fi
		else 
			failures[$f_index]="iptables OS_FIREWALL_ALLOW rule: $node is not fixed."
			((f_index++))
		fi
	done
}

check_cdn_dns_config()
{
	for node in ${backend_nodes[*]};
	do
		s_count=`ssh -l root $node -i $dplyr_identity "cat /etc/dnsmasq.d/origin-dns.conf | grep "server=" | wc -l" 2> /dev/null`
		if [[ "$s_count" -ge "2" ]]; then
			success[$s_index]="DNS config for CDN(svr): $node is OK."
			((s_index++))
		else 
			failures[$f_index]="DNS config for CDN(svr): $node is missing."
			((f_index++))
		fi

		s_count=`ssh -l root $node -i $dplyr_identity "cat /etc/dnsmasq.d/origin-dns.conf | grep "max-cache-ttl" | cut -d'=' -s -f2" 2> /dev/null`
		if [[ "$s_count" -ge "15" ]]; then
			success[$s_index]="DNS config for CDN(ttl): $node is OK."
			((s_index++))
		else 
			failures[$f_index]="DNS config for CDN(ttl): $node is missing."
			((f_index++))
		fi
	done
}

print_failures()
{
	echo "#### Listing all the errors encountered #####"
	idx=0
	while [ "$idx" -lt "${#failures[*]}" ]; 
	do
		echo "ERROR: ${failures[$idx]}"
		((idx++))
	done

	if [ "${#failures[*]}" == "0" ]; then
		echo "Great! NO Errors found. Total errors: ${#failures[*]} #####"
	else
		echo "Total errors: ${#failures[*]} ###############"
	fi

	echo "#############################################"
}

check_node_labels()
{
	for node in ${nodes[*]};
	do
		labels=(`oc get node $node --show-labels | grep -v NAME | sed -e "s/,/ /g"`)
		for label in ${labels[*]};
		do
			if [[ "$label" =~ "$node_label/type=backend" ]]; then
				backend_nodes[$b_index]="$node"
				((b_index++))
			fi

			if [[ "$label" =~ "$node_label/type=master" ]]; then
				ipvs_nodes[$i_index]="$node"
				((i_index++))
			fi

			if [[ "$label" =~ "infra.cisco.com/type=infra" ]]; then
				infra_nodes[$infra_index]="$node"
				((infra_index++))
			fi
		done
	done

	if [ "${#ipvs_nodes[*]}" == "2" ]; then
		success[$s_index]="All IPVS Nodes are found: Count: ${#ipvs_nodes[*]} ...OK"
		((s_index++))
	else 
		failures[$f_index]="Not all IPVS Nodes are discovered, count: ${#ipvs_nodes[*]}, required: 2"
		((f_index++))
	fi

	if [ "${#infra_nodes[*]}" == "3" ]; then
		success[$s_index]="All INFRA Nodes are found: Count: ${#infra_nodes[*]} ...OK"
		((s_index++))
	else 
		failures[$f_index]="Not all INFRA Nodes are discovered, count: ${#infra_nodes[*]}, required: 3"
		((f_index++))
	fi
}

print_success()
{
	echo "#### Listing all the Success results #####"
	idx=0
	while [ "$idx" -lt "${#success[*]}" ]; 
	do
		echo "SUCCESS: ${success[$idx]}"
		((idx++))
	done

	echo "#############################################"
}

print_backend_nodes()
{
	echo "#### Verifying Backend Nodes through Labels #####"

	for node in ${backend_nodes[*]}; 
	do
		echo "FOUND: Backend Node ==> $node"
	done

	echo "-------------------------------"

	echo "Total Backend Nodes: ${#backend_nodes[*]} #####"

	echo "###############################"
}

print_ipvs_nodes()
{
	echo "#### Verifying IPVS Nodes through Labels #####"

	for node in ${ipvs_nodes[*]}; 
	do
		echo "FOUND: IPVS Node ==> $node"
	done

	echo "-------------------------------"

	echo "Total IPVS Nodes: ${#ipvs_nodes[*]} #####"

	echo "###############################"
}

print_infra_nodes()
{
	echo "#### Verifying INFRA Nodes through Labels #####"

	for node in ${infra_nodes[*]}; 
	do
		echo "FOUND: INFRA Node ==> $node"
	done

	echo "-------------------------------"

	echo "Total INFRA Nodes: ${#infra_nodes[*]} #####"

	echo "###############################"
}

usage()
{
	echo ""
	echo "$0 -m ocp-master -u ocp-user -p ocp-passwd [-l node-label-key] [-i deployer-identity(sshkey)]"
	echo "INFO: node-label-key examples: cisco.com(default), ipvs.cisco.com, infra.cisco.com"
	echo ""
}

parse_args()
{
	for i in "$@"
	do
	case $i in
		-h | --help)
		usage
		exit 0
		;;
    		-m)
		 if [ -n "$2" ]; then
    			OCP_MASTER="$2"
                	shift
            	else
                	echo -e "ERROR: '$1' requires an argument.\n" >&2
                	exit 1
            	fi
		shift
    		;;
    		-u)
		 if [ -n "$2" ]; then
    			OCP_USER="$2"
                	shift
            	else
                	echo -e "ERROR: '$1' requires an argument.\n" >&2
                	exit 1
            	fi
		shift
    		;;
    		-p)
		 if [ -n "$2" ]; then
    			OCP_PASSWD="$2"
                	shift
            	else
                	echo -e "ERROR: '$1' requires an argument.\n" >&2
                	exit 1
            	fi
		shift
    		;;
    		-l)
		 if [ -n "$2" ]; then
    			NODE_LABEL="$2"
                	shift
            	else
                	echo -e "ERROR: '$1' requires an argument.\n" >&2
                	exit 1
            	fi
		shift
    		;;
    		-i)
		 if [ -n "$2" ]; then
    			DPL_IDENTITY="$2"
                	shift
            	else
                	echo -e "ERROR: '$1' requires an argument.\n" >&2
                	exit 1
            	fi
		shift
    		;;
    		*)
    		;;
	esac
	done

	if [ -z "$OCP_MASTER" ]; then
		usage
		exit
	fi

	if [ -z "$OCP_USER" ]; then
		usage
		exit
	fi

	if [ -z "$OCP_PASSWD" ]; then
		usage
		exit
	fi

	if [ -z "$NODE_LABEL" ]; then
		node_label="cisco.com"
        else
		node_label=$NODE_LABEL
	fi

	if [ -z "$DPL_IDENTITY" ]; then
                dplyr_identity="/root/ivp-coe/sshkeys/ivp-deployer"
        else
		dplyr_identity=$DPL_IDENTITY
	fi
}

login()
{
	master_node=$1
        user=$2
        passwd=$3

	echo "INFO: connecting to master-node: $master_node"

	oc login -u $user -p $passwd --insecure-skip-tls-verify=false "https://$master_node:8443" -n ipvs-service >& /dev/null

	nodes=(`oc get nodes | grep -v NAME | grep -v SchedulingDisabled | awk '{ print $1 }'`)
}

parse_args $@
login $OCP_MASTER $OCP_USER $OCP_PASSWD $DPL_IDENTITY
check_node_labels
print_backend_nodes
print_ipvs_nodes
print_infra_nodes
check_lo_vip_on_backend_nodes
check_sysctl_info_for_backend_nodes
check_network_labels_of_backend_nodes
check_network_labels_of_ipvs_nodes
check_ipvs_iptables_reset_connection
check_cdn_dns_config
print_success
print_failures

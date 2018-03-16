
#######################################################
# Project: Install-ingress-objects
# Script:  Run Ingress controller once for OCP-Master,
#          Grafana, AlertManager, Prometheus Services.
#          Restart: HAProxy
# Author:  Neeraj Sharma
# Date:    01/24/2018
#######################################################

declare -a success
s_index=0

declare -a failues
f_index=0

declare -a lb_ip_nodes
declare -a lb_name_nodes
lb_index=0

declare -a master_ip_nodes
declare -a master_name_nodes
m_index=0

user="system"
passwd="admin"

lb_vip=""
lb_section=0
master_section=0

ocpmaster="atomic-openshift-api"
grafana="atomic-grafana-openshift-api"
alertmgr="atomic-alertmanager-openshift-api"
prometheus="atomic-prometheus-openshift-api"

ocpmaster_port=8443
grafana_port=3000
alertmgr_port=9093
prometheus_port=9090

master_0=""
master_1=""
master_2=""

ocpmaster_block=""
grafana_block=""
alertmgr_block=""
prometheus_block=""

service_block=""

get_service_block()
{
service=$1
service_port=$2

service_block="
frontend  atomic-$service-api
    bind *:$service_port
    default_backend atomic-$service-api
    mode tcp
    option tcplog

backend atomic-$service-api
    balance source
    mode tcp
    server      master0 $master_0:$service_port check
    server      master1 $master_1:$service_port check
    server      master2 $master_2:$service_port check
"
}

get_master_and_lb_nodes()
{
	while read aline;
	do
		if [[ "$aline" =~ ^"keepalived_vip=" ]]; then
			lb_vip=`echo $aline |  sed -e "s/^keepalived_vip=//"`
		fi

		if [[ "$aline" =~ ^"[masters]" ]]; then
			master_section=1
			continue
		fi
		if [ $master_section == "1" ]; then
			master_node=`echo $aline | awk '{ print $1 }'`
			if [[ ! "$master_node" =~ ^"#" ]]; then
				master_name_nodes[m_index]=`echo $aline | awk '{ print $1 }'`
				master_ip_nodes[m_index]=`echo $aline | awk '{ print $3 }' | sed -e "s/openshift_ip=//"`
				((m_index++))
			fi
			if [ "$m_index" == "3" ]; then
				master_section=0
			fi
		fi

		if [[ "$aline" =~ ^"[lb]" ]]; then
			lb_section=1
			continue
		fi
		if [ $lb_section == "1" ]; then
			lb_node=`echo $aline | awk '{ print $1 }'`
			if [[ ! "$lb_node" =~ ^"#" ]]; then
				lb_name_nodes[lb_index]=`echo $aline | awk '{ print $1 }'`
				lb_ip_nodes[lb_index]=`echo $aline | awk '{ print $3 }' | sed -e "s/openshift_ip=//"`
				((lb_index++))
			fi
			if [ "$lb_index" == "2" ]; then
				lb_section=0
			fi
		fi

	done < $inventory_file
}

check_and_place_haproxy_config()
{
	for node in ${lb_ip_nodes[*]};
	do
		haProxyConf=`ssh -l root $node -i $dplyr_identity "cat /etc/haproxy/haproxy.cfg" 2> /dev/null`
		o_count=`echo "$haProxyConf" | grep "$ocpmaster" | wc -l 2> /dev/null`
		if [[ "$o_count" -ge "3" ]]; then
			success[$s_index]="OCP-Master config for HAProxy: $node is OK."
			((s_index++))
		else 
			if [ "$ocpmaster_block" != "" ]; then
				echo "************** PLACING OCP-Master Block. ************"
				echo "$ocpmaster_block"
				echo "*****************************************************"
			else
				failures[$f_index]="OCP-Master config for HAProxy: $node is missing."
				((f_index++))
			fi
		fi

		g_count=`echo "$haProxyConf" | grep "$grafana" | wc -l 2> /dev/null`
		if [[ "$g_count" -ge "3" ]]; then
			success[$s_index]="Grafana config for HAProxy: $node is OK."
			((s_index++))
		else 
			if [ "$grafana_block" != "" ]; then
				echo "************** PLACING Grafana Block. ***************"
				echo "$grafana_block"
				place_rule=`ssh -l root $node -i $dplyr_identity "echo \"$grafana_block\" >> /etc/haproxy/haproxy.cfg" 2> /dev/null`
				if [ ! $? ]; then
					failures[$f_index]="Grafana config for HAProxy: $node is missing."
					((f_index++))
				else
					success[$s_index]="Grafana config for HAProxy: $node is OK."
					((s_index++))
				fi
				echo "*****************************************************"
			else
				failures[$f_index]="Grafana config for HAProxy: $node is missing."
				((f_index++))
			fi
		fi

		a_count=`echo "$haProxyConf" | grep "$alertmgr" | wc -l 2> /dev/null`
		if [[ "$a_count" -ge "3" ]]; then
			success[$s_index]="AlertManager config for HAProxy: $node is OK."
			((s_index++))
		else 
			if [ "$alertmgr_block" != "" ]; then
				echo "************** PLACING AlertMgr Block. **************"
				echo "$alertmgr_block"
				place_rule=`ssh -l root $node -i $dplyr_identity "echo \"$alertmgr_block\" >> /etc/haproxy/haproxy.cfg" 2> /dev/null`
				if [ ! $? ]; then
					failures[$f_index]="AlertManager config for HAProxy: $node is missing."
					((f_index++))
				else
					success[$s_index]="AlertManager config for HAProxy: $node is OK."
					((s_index++))
				fi
				echo "*****************************************************"
			else
				failures[$f_index]="AlertManager config for HAProxy: $node is missing."
				((f_index++))
			fi
		fi

		p_count=`echo "$haProxyConf" | grep "$prometheus" | wc -l 2> /dev/null`
		if [[ "$p_count" -ge "3" ]]; then
			success[$s_index]="Prometheus config for HAProxy: $node is OK."
			((s_index++))
		else 
			if [ "$prometheus_block" != "" ]; then
				echo "************** PLACING Prometheus Block. ***************"
				echo "$prometheus_block"
				place_rule=`ssh -l root $node -i $dplyr_identity "echo \"$prometheus_block\" >> /etc/haproxy/haproxy.cfg" 2> /dev/null`
				if [ ! $? ]; then
					failures[$f_index]="Prometheus config for HAProxy: $node is missing."
					((f_index++))
				else
					success[$s_index]="Prometheus config for HAProxy: $node is OK."
					((s_index++))
				fi
				echo "*****************************************************"
			else
				failures[$f_index]="Prometheus config for HAProxy: $node is missing."
				((f_index++))
			fi
		fi
	done
}

check_and_place_iptables_rules()
{
	for node in ${lb_ip_nodes[*]};
	do
		ocpmaster_rule=`ssh -l root $node -i $dplyr_identity "iptables -L OS_FIREWALL_ALLOW  -n | grep '^ACCEPT' | grep 'tcp dpt:$ocpmaster_port$'" 2> /dev/null`
		if [[ "$ocpmaster_rule" != "" ]]; then
			rule_ok=`echo $ocpmaster_rule | grep "state NEW"`
			if [[ "$rule_ok" != "" ]]; then
				success[$s_index]="iptables OS_FIREWALL_ALLOW rule for OCP-Master: $node is OK."
				((s_index++))
			else 
				failures[$f_index]="iptables OS_FIREWALL_ALLOW rule for OCP-Master: $node is not fixed."
				((f_index++))
			fi
		else
			place_rule=`ssh -l root $node -i $dplyr_identity "iptables -A OS_FIREWALL_ALLOW -m state --state NEW -m tcp -p tcp --dport $ocpmaster_port -j ACCEPT" 2> /dev/null`
			if [ ! $? ]; then
				failures[$f_index]="iptables OS_FIREWALL_ALLOW rule for OCP-Master: $node is not fixed."
				((f_index++))
			else
				success[$s_index]="iptables OS_FIREWALL_ALLOW rule for OCP-Master: $node is OK."
				((s_index++))
			fi
		fi

		grafana_rule=`ssh -l root $node -i $dplyr_identity "iptables -L OS_FIREWALL_ALLOW  -n | grep '^ACCEPT' | grep 'tcp dpt:$grafana_port$'" 2> /dev/null`
		if [[ "$grafana_rule" != "" ]]; then
			rule_ok=`echo $grafana_rule | grep "state NEW"`
			if [[ "$rule_ok" != "" ]]; then
				success[$s_index]="iptables OS_FIREWALL_ALLOW rule for Grafana: $node is OK."
				((s_index++))
			else 
				failures[$f_index]="iptables OS_FIREWALL_ALLOW rule for Grafana: $node is not fixed."
				((f_index++))
			fi
		else 
			place_rule=`ssh -l root $node -i $dplyr_identity "iptables -A OS_FIREWALL_ALLOW -m state --state NEW -m tcp -p tcp --dport $grafana_port -j ACCEPT" 2> /dev/null`
			if [ ! $? ]; then
				failures[$f_index]="iptables OS_FIREWALL_ALLOW rule for Grafana: $node is not fixed."
				((f_index++))
			else
				success[$s_index]="iptables OS_FIREWALL_ALLOW rule for Grafana: $node is OK."
				((s_index++))
			fi
		fi

		alertmgr_rule=`ssh -l root $node -i $dplyr_identity "iptables -L OS_FIREWALL_ALLOW  -n | grep '^ACCEPT' | grep 'tcp dpt:$alertmgr_port$'" 2> /dev/null`
		if [[ "$alertmgr_rule" != "" ]]; then
			rule_ok=`echo $alertmgr_rule | grep "state NEW"`
			if [[ "$rule_ok" != "" ]]; then
				success[$s_index]="iptables OS_FIREWALL_ALLOW rule for AlertManager: $node is OK."
				((s_index++))
			else 
				failures[$f_index]="iptables OS_FIREWALL_ALLOW rule for AlertManager: $node is not fixed."
				((f_index++))
			fi
		else 
			place_rule=`ssh -l root $node -i $dplyr_identity "iptables -A OS_FIREWALL_ALLOW -m state --state NEW -m tcp -p tcp --dport $alertmgr_port -j ACCEPT" 2> /dev/null`
			if [ ! $? ]; then
				failures[$f_index]="iptables OS_FIREWALL_ALLOW rule for AlertManager: $node is not fixed."
				((f_index++))
			else
				success[$s_index]="iptables OS_FIREWALL_ALLOW rule for AlertManager: $node is OK."
				((s_index++))
			fi
		fi

		prometheus_rule=`ssh -l root $node -i $dplyr_identity "iptables -L OS_FIREWALL_ALLOW  -n | grep '^ACCEPT' | grep 'tcp dpt:$prometheus_port$'" 2> /dev/null`
		if [[ "$prometheus_rule" != "" ]]; then
			rule_ok=`echo $prometheus_rule | grep "state NEW"`
			if [[ "$rule_ok" != "" ]]; then
				success[$s_index]="iptables OS_FIREWALL_ALLOW rule for Prometheus: $node is OK."
				((s_index++))
			else 
				failures[$f_index]="iptables OS_FIREWALL_ALLOW rule for Prometheus: $node is not fixed."
				((f_index++))
			fi
		else 
			place_rule=`ssh -l root $node -i $dplyr_identity "iptables -A OS_FIREWALL_ALLOW -m state --state NEW -m tcp -p tcp --dport $prometheus_port -j ACCEPT" 2> /dev/null`
			if [ ! $? ]; then
				failures[$f_index]="iptables OS_FIREWALL_ALLOW rule for Prometheus: $node is not fixed."
				((f_index++))
			else
				success[$s_index]="iptables OS_FIREWALL_ALLOW rule for Prometheus: $node is OK."
				((s_index++))
			fi
		fi
	done
}

restart_haproxy_service()
{
	for node in ${lb_ip_nodes[*]};
	do
		if [ "$haproxy_restart" == "yes" ]; then
			echo "---------- Restarting HAPROXY -------------"
			restart_result=`ssh -l root $node -i $dplyr_identity "systemctl restart haproxy.service" 2> /dev/null`
			if [ ! $? ]; then
				failures[$f_index]="HAProxy restart: $node ...failed."
				((f_index++))
			else
				success[$s_index]="HAProxy restart: $node  ...OK."
				((s_index++))
			fi
			echo "----------------- Done --------------------"
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

print_master_nodes()
{
	echo "#### Discovering MASTER Nodes from inventory file #####"

	idx=0

	for node in ${master_name_nodes[*]}; 
	do
		echo "FOUND: MASTER Node ==> $node (${master_ip_nodes[$idx]})"
		((idx++))
	done

	echo "-------------------------------"

	echo "Total MASTER Nodes: ${#master_name_nodes[*]} #####"

	echo "###############################"
}

print_lb_nodes()
{
	echo "#### Discovering LB Nodes from inventory file #####"

	echo "FOUND:     VIP ==> $lb_vip"

	idx=0

	for node in ${lb_name_nodes[*]}; 
	do
		echo "FOUND: LB Node ==> $node (${lb_ip_nodes[$idx]})"
		((idx++))
	done

	echo "-------------------------------"

	echo "Total LB Nodes: ${#lb_name_nodes[*]} #####"

	echo "###############################"
}

login()
{
	echo "INFO: connecting to lb-vip: $lb_vip"

	oc login -u $user -p $passwd --insecure-skip-tls-verify=false "https://$lb_vip:8443" -n default >& /dev/null

	nodes=(`oc get nodes | grep -v NAME | grep SchedulingDisabled | awk '{ print $1 }'`)

	echo "INFO: connection to lb-vip: $lb_vip ... OK."

	if [ "${#nodes[*]}" == "${#master_name_nodes[*]}" ]; then
		success[$s_index]="OCP Cluster reported masters: (${nodes[*]}), check ..OK."
		((s_index++))
		if [ "${#master_ip_nodes[*]}" == "3" ]; then
			master_0=${master_ip_nodes[0]}
			master_1=${master_ip_nodes[1]}
			master_2=${master_ip_nodes[2]}
		fi
	else
		failures[$f_index]="OCP Cluster reported masters: (${nodes[*]}), check failed."
		((f_index++))
	fi

	if [ "$master_0" != "" -a "$master_1" != "" -a "$master_2" != "" ]; then
		get_service_block openshift $ocpmaster_port
		ocpmaster_block="$service_block"

		get_service_block grafana-openshift $grafana_port
		grafana_block="$service_block"

		get_service_block alertmanager-openshift $alertmgr_port
		alertmgr_block="$service_block"

		get_service_block prometheus-openshift $prometheus_port
		prometheus_block="$service_block"

		#echo "$ocpmaster_block"
		#echo "$grafana_block"
		#echo "$alertmgr_block"
		#echo "$prometheus_block"
	fi
}

usage()
{
	echo ""
	echo "$0 -f inventory-file [-i deployer-identity(sshkey)] [ -r restart-haproxy ]"
	echo "INFO: inventory-file is expected to be present in /root/ivp-coe dir OR provide with absolute path."
	echo "      -r restart-haproxy: default is no. Please provide yes if needed. Example: -r yes "
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
    		-f)
		 if [ -n "$2" ]; then
    			INVENTORY_FILE="$2"
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
    		-r)
		 if [ -n "$2" ]; then
    			HAPROXY_RESTART="$2"
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

	if [ -z "$INVENTORY_FILE" ]; then
		usage
		exit
	fi

	if [[ "$INVENTORY_FILE" =~ "/" ]]; then
		inventory_file=$INVENTORY_FILE
        else
		inventory_file=/root/ivp-coe/$INVENTORY_FILE
	fi

	if [ -z "$DPL_IDENTITY" ]; then
                dplyr_identity="/root/ivp-coe/sshkeys/ivp-deployer"
        else
		dplyr_identity=$DPL_IDENTITY
	fi

	if [ -z "$HAPROXY_RESTART" ]; then
		haproxy_restart="no"
	else
		haproxy_restart="$HAPROXY_RESTART"
	fi

        if [ ! -e $inventory_file ]; then
		echo "ERROR: file not found: $inventory_file"
		exit
	fi

        if [ ! -e $dplyr_identity ]; then
		echo "ERROR: file not found: $dplyr_identity"
		exit
	fi

	echo "INFO: HAProxy restart option: $haproxy_restart"
}

parse_args $@
echo "---------------------------------"
echo "Good: File found: $inventory_file"
echo "---------------------------------"
get_master_and_lb_nodes
print_master_nodes
print_lb_nodes
login
check_and_place_haproxy_config
check_and_place_iptables_rules
restart_haproxy_service
print_success
print_failures

#!/bin/bash

#parameters
randomstring=$(cat /dev/urandom | tr -dc 'a-z0-9' | fold -w 15 | head -n 1)
location='eastus' #location of Azure Spring Cloud Virtual Network
hub_vnet_name='hub-vnet' #Hub Virtual Network Name
hub_vnet_resource_group_name='hub-vnet-rg' #Hub Virtual Network Resource Group name
hub_vnet_address_prefixes='10.9.0.0/16' #Hub Virtual Network Address Prefixes
firewal_subnet_prefix='10.9.0.0/24' #Address prefix of 
centralized_services_subnet_name='centralized-services-subnet'
centralized_services_subnet_prefix='10.9.1.0/24'
gateway_subnet_prefix='10.9.2.0/24'
bastion_subnet_prefix='10.9.4.0/24'
application_gateway_subnet_name='application-gateway-subnet'
application_gateway_subnet_prefix='10.9.3.0/24'
firewall_name='azfirewall' #Name of Azure firewall resource
firewall_public_ip_name='azfirewall-pip2' #Azure firewall public ip resource name
azure_key_vault_name='akv-'$randomstring #Azure Key vault unique name
azurespringcloud_vnet_resource_group_name='azurespringcloud-spoke-vnet-rg' #parameter for Azure Spring Cloud Virtual network resource group name
azurespringcloud_vnet_name='azurespringcloud-spoke-vnet' #parameter for Azure Spring Cloud Vnet name
azurespringcloud_vnet_address_prefixes='10.8.0.0/16' #address prefix of Azure Spring Cloud Virtual Network
azurespringcloud_service_runtime_subnet_prefix='10.8.0.0/24' #subnet prefix of Azure Spring Cloud 
azurespringcloud_service_runtime_subnet_name='service-runtime-subnet'
azurespringcloud_app_subnet_prefix='10.8.1.0/24'
azurespringcloud_app_subnet_name='apps-subnet'
azurespringcloud_resource_group_name='azspringcloud-rg' #Hub Virtual Network Resource Group name
azurespringcloud_service='azspringcloud-'$randomstring #Name of unique Spring Cloud resource
azurespringcloud_service_runtime_resource_group_name=$azurespringcloud_service'-service-runtime-rg' #Name of Azure Spring Cloud service runtime resource group	
azurespringcloud_app_resource_group_name=$azurespringcloud_service'-apps-rg' #Name of Azure Spring Cloud apps resource group

echo "Enter full UPN of Key Vault Admin: "
read userupn
admin_object_id=$(az ad user show --id $userupn --query objectId --output tsv)

echo "create hub vnet rg"

az group create --location ${location} --name ${hub_vnet_resource_group_name}

echo create hub vnet

az network vnet create \
    --name ${hub_vnet_name} \
    --resource-group ${hub_vnet_resource_group_name} \
    --location ${location} \
    --address-prefixes ${hub_vnet_address_prefixes}

az network vnet subnet create \
    --name 'AzureFirewallSubnet' \
    --resource-group ${hub_vnet_resource_group_name} \
    --vnet-name ${hub_vnet_name} \
    --address-prefix ${firewal_subnet_prefix}

az network vnet subnet create \
    --name ${centralized_services_subnet_name} \
    --resource-group ${hub_vnet_resource_group_name}  \
    --vnet-name ${hub_vnet_name} \
    --address-prefix ${centralized_services_subnet_prefix}

az network vnet subnet create \
    --name 'GatewaySubnet' \
    --resource-group ${hub_vnet_resource_group_name} \
    --vnet-name ${hub_vnet_name} \
    --address-prefix ${gateway_subnet_prefix}

az network vnet subnet create \
    --name ${application_gateway_subnet_name} \
    --resource-group ${hub_vnet_resource_group_name} \
    --vnet-name ${hub_vnet_name} \
    --address-prefix ${application_gateway_subnet_prefix}

az network vnet subnet create \
    --name AzureBastionSubnet \
    --resource-group ${hub_vnet_resource_group_name} \
    --vnet-name ${hub_vnet_name} \
    --address-prefix ${bastion_subnet_prefix}

echo all subnets and vnet created

echo create FW
az network firewall create \
    --name ${firewall_name} \
    --resource-group ${hub_vnet_resource_group_name} \
    --location ${location} \
    --enable-dns-proxy true
az network public-ip create \
    --name ${firewall_public_ip_name} \
    --resource-group ${hub_vnet_resource_group_name} \
    --location ${location} \
    --allocation-method static \
    --sku standard
az network firewall ip-config create \
    --firewall-name ${firewall_name} \
    --name FW-config \
    --public-ip-address ${firewall_public_ip_name} \
    --resource-group ${hub_vnet_resource_group_name}\
    --vnet-name ${hub_vnet_name}
az network firewall update \
    --name ${firewall_name}  \
    --resource-group ${hub_vnet_resource_group_name}
firewall_private_ip="$(az network firewall ip-config list -g ${hub_vnet_resource_group_name} -f ${firewall_name} --query "[?name=='FW-config'].privateIpAddress" --output tsv)"

echo create FW network rules
az network firewall network-rule create \
    --collection-name SpringCloudAccess \
    --destination-ports 123 \
    --firewall-name ${firewall_name} \
    --name NtpQuery \
    --protocols UDP \
    --resource-group ${hub_vnet_resource_group_name} \
    --action Allow \
    --destination-addresses * \
    --source-addresses ${azurespringcloud_app_subnet_prefix} ${azurespringcloud_service_runtime_subnet_prefix}
    --priority 100
echo Finished creating FW rules

echo create Azure spring cloud vnet rg

az group create --location ${location} --name ${azurespringcloud_vnet_resource_group_name}

echo create azure spring cloud spoke vnet

az network vnet create \
    --name ${azurespringcloud_vnet_name} \
    --resource-group ${azurespringcloud_vnet_resource_group_name} \
    --location ${location} \
    --address-prefixes ${azurespringcloud_vnet_address_prefixes}

#Create Azure Spring Cloud apps subnet
az network vnet subnet create  \
    --name ${azurespringcloud_service_runtime_subnet_name} \
    --resource-group ${azurespringcloud_vnet_resource_group_name} \
    --vnet-name ${azurespringcloud_vnet_name} \
    --address-prefix ${azurespringcloud_service_runtime_subnet_prefix}

#Create Azure Spring Cloud App Subnet
az network vnet subnet create \
    --name ${azurespringcloud_app_subnet_name} \
    --resource-group ${azurespringcloud_vnet_resource_group_name} \
    --vnet-name ${azurespringcloud_vnet_name} \
    --address-prefix ${azurespringcloud_app_subnet_prefix}

echo finished creating azure spring cloud subnets and vnet

#Get Resource ID  for Azure Spring Cloud Vnet
azurespringcloud_vnet_id=$(az network vnet show \
    --resource-group ${azurespringcloud_vnet_resource_group_name} \
    --name ${azurespringcloud_vnet_name} \
    --query id --out tsv)

#Get Resource ID for Hub Vnet
hub_vnet_id=$(az network vnet show \
    --resource-group ${hub_vnet_resource_group_name} \
    --name ${hub_vnet_name} \
    --query id --out tsv)

echo assign owner to Azure Spring Cloud spoke

az role assignment create \
    --role "Owner" \
    --scope ${azurespringcloud_vnet_id} \
    --assignee e8de9221-a19c-4c81-b814-fd37c6caf9d2

echo owner role is added

echo create peering from Spring cloud vnet to hub vnet

az network vnet peering create \
    --name azurespringcloud_vnet_to_hub_vnet \
    --resource-group ${azurespringcloud_vnet_resource_group_name} \
    --vnet-name ${azurespringcloud_vnet_name} \
    --remote-vnet ${hub_vnet_name} \
    --allow-vnet-access

echo finished peering ASC spoke to hub Vnet

echo create peering from hub vnet to Spring cloud vnet

#Peer Hub Vnet to Azure Spring Cloud Spoke VNet
az network vnet peering create \
    --name hub_vnet_to_azurespringcloud_vnet \
    --resource-group ${hub_vnet_resource_group_name} \
    --vnet-name ${hub_vnet_name} \
    --remote-vnet ${azurespringcloud_vnet_id} \
   --allow-vnet-access

echo finished peering of hub to ASC spoke

echo create Azure Spring Cloud Resource group

az group create --location ${location} --name ${azurespringcloud_resource_group_name}

echo creating spring cloud AKV
az keyvault create --name ${azure_key_vault_name} --resource-group ${azurespringcloud_resource_group_name} --location ${location} --no-self-perms
echo finished creating azure spring cloud akv

az keyvault set-policy --name ${azure_key_vault_name} --object-id $admin_object_id  --key-permissions backup create decrypt delete encrypt get import list purge recover restore sign unwrapKey update verify wrapKey --secret-permissions backup delete get list purge recover restore set --certificate-permissions backup create delete deleteissuers get getissuers import list listissuers managecontacts manageissuers purge recover restore setissuers update


echo Getting app subnet id

apps_subnet_id=$(az network vnet subnet show \
    --resource-group ${azurespringcloud_vnet_resource_group_name} \
    --vnet-name ${azurespringcloud_vnet_name} \
    --name ${azurespringcloud_app_subnet_name} \
    --query id --output tsv)

echo got app subnet id.  Id is $apps_subnet_id

echo getting service runtime subnet id

service_runtime_subnet_id=$(az network vnet subnet show \
    --resource-group ${azurespringcloud_vnet_resource_group_name} \
    --vnet-name ${azurespringcloud_vnet_name} \
    --name ${azurespringcloud_service_runtime_subnet_name} \
    --query id --output tsv)

echo id is $service_runtime_subnet_id

echo creating spring cloud

az spring-cloud create \
    --name ${azurespringcloud_service} \
    --resource-group ${azurespringcloud_resource_group_name} \
    --location ${location} \
    --app-network-resource-group ${azurespringcloud_app_resource_group_name} \
    --service-runtime-network-resource-group ${azurespringcloud_service_runtime_resource_group_name} \
    --vnet ${azurespringcloud_vnet_id} \
    --service-runtime-subnet ${service_runtime_subnet_id} \
    --app-subnet ${apps_subnet_id}

echo finished creating spring cloud

echo starting routetable

azurespringcloud_app_resourcegroup_name=$(az spring-cloud show \
    --resource-group ${azurespringcloud_resource_group_name} \
    --name ${azurespringcloud_service} \
    --query 'properties.networkProfile.appNetworkResourceGroup' --output tsv )

azurepringcloud_app_routetable_name=$(az network route-table list \
    --resource-group ${azurespringcloud_app_resourcegroup_name} \
    --query [].name --output tsv)

az network route-table route create \
    --resource-group ${azurespringcloud_app_resourcegroup_name} \
    --route-table-name ${azurepringcloud_app_routetable_name} \
    --name default \
    --address-prefix 0.0.0.0/0 \
    --next-hop-type VirtualAppliance \
    --next-hop-ip-address ${firewall_private_ip}

echo finished apps route table

echo starting route table

#Add UDR in service subnet route table for NVA
azurespringcloud_service_resourcegroup_name=$(az spring-cloud show \
    --resource-group ${azurespringcloud_resource_group_name} \
    --name ${azurespringcloud_service} \
    --query 'properties.networkProfile.serviceRuntimeNetworkResourceGroup' --out tsv )

azurepringcloud_service_routetable_name=$(az network route-table list \
    --resource-group ${azurespringcloud_service_resourcegroup_name} \
    --query [].name --out tsv)

az network route-table route create \
    --resource-group ${azurespringcloud_service_resourcegroup_name} \
    --route-table-name ${azurepringcloud_service_routetable_name} \
    --name default \
    --address-prefix 0.0.0.0/0 \
    --next-hop-type VirtualAppliance \
    --next-hop-ip-address ${firewall_private_ip}

echo finished service runtime route table

echo creating private dns zone

#Create Private DNS Zone for Azure Spring Cloud
az network private-dns zone create \
    --resource-group ${azurespringcloud_resource_group_name} \
    --name private.azuremicroservices.io

echo creating link to Azure Spring Cloud Vnet

#Link Private DNS Zone to Azure Spring Cloud VNet
az network private-dns link vnet create \
    --resource-group ${azurespringcloud_resource_group_name} \
    --name link-to-${azurespringcloud_vnet_name} \
    --zone-name private.azuremicroservices.io \
    --virtual-network ${azurespringcloud_vnet_id} \
    --registration-enabled false

echo creating link to Hub Vnet

#Link Private DNS Zone to Hub VNet
az network private-dns link vnet create \
    --resource-group ${azurespringcloud_resource_group_name} \
    --name link-to-${hub_vnet_name} \
    --zone-name private.azuremicroservices.io \
    --virtual-network ${hub_vnet_id}\
    --registration-enabled false

echo getting ilb private ip

#Get Azure Spring Cloud service runtime subnet internal load balancer private IP address
azurespringcloud_internal_lb_private_ip=$(az network lb show --name kubernetes-internal \
    --resource-group ${azurespringcloud_service_runtime_resource_group_name_resourcegroup_name} \
    --query frontendIpConfigurations[*].privateIpAddress --out tsv )
#Add A record in Private DNS Zone for internal Azure Spring Cloud load balancer

echo starting to add A record for ILB load balancer
az network private-dns record-set a add-record \
    --resource-group ${azurespringcloud_resource_group_name} \
    --zone-name private.azuremicroservices.io \
    --record-set-name '*' \
    --ipv4-address ${azurespringcloud_internal_lb_private_ip}

echo finished adding A record
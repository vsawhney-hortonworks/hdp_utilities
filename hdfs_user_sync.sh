#!/bin/sh

# © 2018 Hortonworks Inc. All Rights Reserved.  This software/code is licensed to you pursuant to the written agreement between Hortonworks and your company.
# If no such written agreement exists, you do not have a license to this software.”
# Author:   Vikas Sawhney (Hortonworks Inc.)
# Date: Oct 23 2018

# About:Script Perform Checks between Active Directory Groups which have access to Hadoop
# 1. Reports and adds Missing users add in AD Group but not in HDFS
# 2. Reports Users no longer in AD but in HDFS
# 3. Emails a list users detailed in 1,2
# Requirements: AD user account that has ability to perform search in ldap tree to lookup users,
#               Hadoop user with permission to check hdfs directories and the ability to create/ home directories users.
# Script requires a input, review sample input.properties
# Usage hdfs_user_sync.sh <path to properties file> ex. hdfs_user_sync.sh user_sync.properties


read -p 'Hostname: ' server
read -p 'Password: ' password
read -p 'Domain_Account: ' domain_account
read -p 'LDAP Search Base: ' ldap_search_base
read -p 'Search Filter: ' search_filter
read -p 'Email To Address: ' email_address

#Stores LDAP users in a array
function ldap_user_search() {
        arr=($(ldapsearch -xLLL -h $server -D $domain_account -w $password -b "$ldap_search_base" "$search_filter" | grep sAMAccountName | cut -c 17- ))
        IFS=$'\n' arr_sort=($(sort -u <<<"${arr[*]}"))
        #echo 'ldapsuers:'
        #printf '%s\n' "${arr_sort[@]}"
        hdfs_user_search
}

# Stores HDFS users in a array
function hdfs_user_search() {
    hdpusers=($(sudo -u hdfs hadoop fs -ls -C /user/ | cut -c 7-))
    #IFS=$'\n' hdpuser_sort=($(sort <<<"${hdpusers[*]"))
    #echo 'hdfsusers:'
    #printf '%s\n' "${hdpusers[@]}"
    hdfs_missing_users
}

# Locates Missing HDFS users which exist in AD
function hdfs_missing_users() {
new_ldap_users=()
for hdpadusers in "${arr_sort[@]}"; do
    skip=
        for hdfsusers in "${hdpusers[@]}"; do
           [[ $hdpadusers == $hdfsusers ]] && { skip=1; break; }
        done
         [[ -n $skip ]] || new_ldap_users+=("$hdpadusers")
done
echo 'users_ldap_in_hdfs:'
printf '%s\n' "${new_ldap_users[@]}"
printf '%s\n' "${new_ldap_users[@]}" > /tmp/hadoop_hdfs_users.$(date +%m%d%Y)
hdfs_orphaned_users
#add_hdfs_users
}

#Locates Orphaned HDFS users which are no longer associated with AD
function hdfs_orphaned_users() {
orphan_hdfs_users=()
for hdfusers in "${hdpusers[@]}"; do
  skip=
  for hdpausers in "${arr_sort[@]}"; do
     [[  $hdfusers == $hdpausers ]] && { skip=1; break; }
   done
   [[ -n $skip ]] || orphan_hdfs_users+=("$hdfusers")
done
echo 'users_missing_in_hdfs:'
printf '%s\n' "${orphan_hdfs_users[@]}"
printf '%s\n' "${orphan_hdfs_users[@]}"  > /tmp/hadoop_orphaned_users.$(date +%m%d%Y)
mail_status
}

# Adds Missing HDFS Users
function add_hdfs_users() {
for new_ad_users in "${new_ldap_users[@]}"; do
  sudo -u hdfs hadoop fs -mkdir /user/$new_ad_users
  sudo -u hdfs hadoop fs -chown $new_ad_users:hdfs /user/$new_ad_users
done
}

# Email Functionality to report missing users in HDFS and AD
function mail_status() {
mailx -s "Daily Status Report Hadoop Users Missing from HDFS" email_address < /tmp/hadoop_hdfs_users.$(date +%m%d%Y)
mailx -s "Daily Status Report Hadoop HDFS Users Not in AD" email_address < /tmp/hadoop_orphaned_users.$(date +%m%d%Y)
#rm /tmp/hadoop_hdfs_users.$(date +%m%d%Y)
#rm /tmp/hadoop_orphaned_users.$(date +%m%d%Y)
}

ldap_user_search

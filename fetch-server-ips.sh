#!/bin/bash

read -p "Please enter client's Email: " email;
read -p "Please enter client's API key: " api_key;

accesstoken="$(curl -s -H "Accept: application/json" -H "Content-Type:application/json" -X POST --data '{"email" : "'$email'", "api_key" : "'$api_key'"}'  'https://api.cloudways.com/api/v1/oauth/access_token'  | jq -r '.access_token')"
curl -s -X GET --header 'Accept: application/json' --header 'Authorization: Bearer '$accesstoken'' 'https://api.cloudways.com/api/v1/server' | jq -r '.servers[] | .public_ip'

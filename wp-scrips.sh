

# Checking wp core checksums for all the applications on server. 
for A in $(ls | awk '{print $NF}');
do
 echo "--------------------" &&
 echo $A && 
 cat /home/master/applications/$A/conf/server.nginx   && 
 cd /home/master/applications/$A/public_html/ &&
 wp core verify-checksums --allow-root || continue
done


echo "------------------ Malware Cleaner ---------------------"
for A in $(ls | awk '{print $NF}'); 
do echo "--------------------" && 
echo $A && cat /home/master/applications/$A/conf/server.nginx   && 
cd /home/master/applications/$A/public_html/ &&
wp core download --force --version=$(wp core version --allow-root) --allow-root || 
cd /home/master/applications/; 
done && cd /home/master/applications/

echo "Removing files that comes in the checksusm warning"
for A in $(ls | awk '{print $NF}'); 
do echo "--------------------" && echo $A && 
cat /home/master/applications/$A/conf/server.nginx && 
cd /home/master/applications/$A/public_html/ && 
wp core verify-checksums --allow-root 2> stderr.txt &&
rm $(cat stderr.txt | awk '{print $6}') && rm stderr.txt || 
cd /home/master/applications/; 
done && cd /home/master/applications/

echo "Creating wp-salt.php"
for A in $(ls | awk '{print $NF}'); 
do echo $A  && cd /home/master/applications/$A/public_html/ && 
input=$(curl https://api.wordpress.org/secret-key/1.1/salt) && 
echo "<?php $input"  > wp-salt.php || cd /home/master/applications/; 
done && cd /home/master/applications/


for A in $(ls | awk '{print $NF}'); 
do echo "--------------------" && 
echo $A && cat /home/master/applications/$A/conf/server.nginx && 
cd /home/master/applications/$A/public_html/ && 
find wp-content/{themes,plugins} -maxdepth 1 -regextype posix-extended -regex '.*/[^/]*[0-9][^/]*' -exec mv {} ../private_html/ \; || cd /home/master/applications/; 
done && cd /home/master/applications/

for A in $(ls | awk '{print $NF}'); 
do echo $A  && cd /home/master/applications/$A/public_html/ && 
mv wp-content/plugins/wp-file-manager ../private_html || cd /home/master/applications/; 
done && cd /home/master/applications/

for A in $(ls | awk '{print $NF}'); 
do echo $A  && cd /home/master/applications/$A/public_html/ && mv wp-content/plugins/PHP-Console_1.2-1 ../private_html || cd /home/master/applications/; 
done && cd /home/master/applications/


echo "------- Reset Permissions -----"
for A in $(ls | awk '{print $NF}'); do echo "--------------------" &&
echo $A && cat /home/master/applications/$A/conf/server.nginx &&
cd /home/master/applications/$A/public_html/ && 
chown $A:www-data -R * && 
ls -al|| cd /home/master/applications/; 
done && cd /home/master/applications/
echo "------- Reset Permissions -----"

echo "------- core verify-checksums -----"
for A in $(ls | awk '{print $NF}'); do echo "--------------------" &&
echo $A && cat /home/master/applications/$A/conf/server.nginx &&
cd /home/master/applications/$A/public_html/
&& wp core verify-checksums --allow-root  || cd /home/master/applications/;
done && cd /home/master/applications/

echo "--------Listing plugins, themes -------"
for A in $(ls | awk '{print $NF}');
do echo "--------------------" && 
echo $A  && cat /home/master/applications/$A/conf/server.nginx  &&
cd /home/master/applications/$A/public_html/ &&
wp plugin list --allow-root && wp theme list --allow-root || 
cd /home/master/applications/;
done && cd /home/master/applications/


for A in $(ls | awk '{print $NF}'); 
do echo "--------------------" &&
echo $A  && cat /home/master/applications/$A/conf/server.nginx &&
cd /home/master/applications/$A/public_html/ &&
wp theme list --allow-root || cd /home/master/applications/;
done && cd /home/master/applications/

for A in $(ls | awk '{print $NF}');
do echo "--------------------" && 
echo $A  && ls -al /home/master/applications/$A/private_html || 
cd /home/master/applications/; 
done && cd /home/master/applications/

echo "---------- Core Malware Cleaner Completed. ---------------------"

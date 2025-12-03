# INstalling promtail main on advasa or any server.
bash <(curl -s https://raw.githubusercontent.com/habdulwajid/cw-script/main/promtail-installer.sh)

# Creating backup. 
bash <(curl -s https://raw.githubusercontent.com/thekazi/scripts.kazi/refs/heads/main/createbackupzip)

#Generalize script with the subscript input
bash <(curl -s https://raw.githubusercontent.com/habdulwajid/cw-script/main/generlize-script.sh)

# WordPress Audit script
curl -H 'Cache-Control: no-cache' -s https://raw.githubusercontent.com/sushantchawla2005/public_scripts/refs/heads/main/wordpress-audit.sh | bash

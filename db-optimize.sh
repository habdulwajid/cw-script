
#PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin
#0 2 * * 1 root /bin/bash /var/cw/scripts/bash/dboptimize.sh ukrxvxuxhf

#!/bin/bash
DATE=$(date "+%F-%H")
WEBHOOK_URL="https://hooks.slack.com/services/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"
DATABASE=$1
SERVERIP=$(curl -s ifconfig.me)
DBSIZEBEFORE=$(du -sh /var/lib/mysql/${DATABASE} | awk '{print $1}')
# Log file for storing optimization results
LOGFILE="/home/master/mysql_optimize.log"

# Exit if there is no argument
if [ $# -lt 1 ]; then
    echo -e "" >> ${LOGFILE}
    echo "SYNTAX: ${PROGNAME} Database" | tee -a ${LOGFILE}
    exit 1
fi

# Run mysqlcheck --optimize on all databases
echo "#### Starting MySQL optimization for database ${DATABASE} on ${DATE} ####" | tee -a ${LOGFILE}

systemctl restart mysql
mysqlcheck_output=$(mysqlcheck --optimize ${DATABASE} 2>&1)
if [ $? -eq 0 ];
then
        DBSIZEAFTER=$(du -sh /var/lib/mysql/${DATABASE} | awk '{print $1}')
        echo "@@@@ MySQL optimization completed successfully. @@@@" | tee -a ${LOGFILE}
        echo "${mysqlcheck_output}" | tee -a ${LOGFILE}
        echo "DB Size Before: ${DBSIZEBEFORE} and DB Size After Optimisation: ${DBSIZEAFTER}"
        curl -X POST -H 'Content-type: application/json' --data '{"text":"MySQL optimization completed successfully on '${SERVERIP}' for Database '${DATABASE}' on '${DATE}' DB Size Before: '${DBSIZEBEFORE}' and DB Size After Opimisation: '${DBSIZEAFTER}'"}' ${WEBHOOK_URL}

    systemctl restart mysql

    # Wait briefly and validate MySQL status
    sleep 3
    MYSQL_STATUS=$(systemctl is-active mysql)

if [ "$MYSQL_STATUS" = "active" ]; then
    echo "MySQL service is running after restart." | tee -a ${LOGFILE}
    systemctl status mysql | tee -a ${LOGFILE}
    exit 0
else
    echo "MySQL service failed to start after restart!" | tee -a ${LOGFILE}
    curl -X POST -H 'Content-type: application/json' \
    --data '{"text":"MySQL service failed to start after optimization on '${SERVERIP}' for '${DATABASE}'."}' \
    ${WEBHOOK_URL}
    exit 2
fi

        exit 0
else
        echo "Error: MySQL optimize failed for ${DATABASE} on ${DATE}" | tee -a ${LOGFILE}
        echo "${mysqlcheck_output}" | tee -a ${LOGFILE}
        curl -X POST -H 'Content-type: application/json' --data '{"text":"MySQL optimization failed on '${SERVERIP}' for Database '${DATABASE}' on '${DATE}'"}' ${WEBHOOK_URL}
        exit 1
fi

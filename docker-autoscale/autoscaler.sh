#!/bin/bash

IMAGE="flask-demo"
PREFIX="flask_"
NETWORK="autoscale-net"
NGINX_CONTAINER="nginx-lb"

MIN_CONTAINERS=1
MAX_CONTAINERS=5

CPU_THRESHOLD_UP=20
CPU_THRESHOLD_DOWN=5

COOLDOWN=15
LAST_SCALE_TIME=0

while true
do
    SCALE_OCCURRED=false
    CURRENT_TIME=$(date +%s)

    CONTAINERS=$(docker ps --filter "name=${PREFIX}" --format "{{.Names}}")
    RUNNING=$(echo "$CONTAINERS" | wc -w)

    TOTAL_CPU=0

    for name in $CONTAINERS
    do
        CPU=$(docker stats --no-stream --format "{{.CPUPerc}}" $name | tr -d '%')
        TOTAL_CPU=$(echo "$TOTAL_CPU + $CPU" | bc)
    done

    if [ "$RUNNING" -gt 0 ]; then
        AVG_CPU=$(echo "scale=2; $TOTAL_CPU / $RUNNING" | bc)
    else
        AVG_CPU=0
    fi

    echo "Running: $RUNNING | Avg CPU: $AVG_CPU%"

    # SCALE UP
    if (( $(echo "$AVG_CPU > $CPU_THRESHOLD_UP" | bc -l) )) && \
       [ "$RUNNING" -lt "$MAX_CONTAINERS" ] && \
       [ $((CURRENT_TIME - LAST_SCALE_TIME)) -gt $COOLDOWN ]
    then
        NEW_ID=$((RUNNING+1))

        docker run -d \
          --name ${PREFIX}${NEW_ID} \
          --network $NETWORK \
          $IMAGE

        echo "Scaled UP → ${PREFIX}${NEW_ID}"

        LAST_SCALE_TIME=$CURRENT_TIME
        SCALE_OCCURRED=true

        sleep 2
    fi

    # SCALE DOWN
    if (( $(echo "$AVG_CPU < $CPU_THRESHOLD_DOWN" | bc -l) )) && \
       [ "$RUNNING" -gt "$MIN_CONTAINERS" ] && \
       [ $((CURRENT_TIME - LAST_SCALE_TIME)) -gt $COOLDOWN ]
    then
        LAST_CONTAINER=$(echo "$CONTAINERS" | sort | tail -n 1)

        docker stop $LAST_CONTAINER
        docker rm $LAST_CONTAINER

        echo "Scaled DOWN → $LAST_CONTAINER"

        LAST_SCALE_TIME=$CURRENT_TIME
        SCALE_OCCURRED=true

        sleep 2
    fi

    # UPDATE NGINX ONLY IF SCALE HAPPENED
    if [ "$SCALE_OCCURRED" = true ]; then
        echo "Updating Nginx upstream..."

        echo "events {}" > nginx.conf
        echo "http {" >> nginx.conf
        echo " upstream backend {" >> nginx.conf

        for name in $(docker ps --filter "name=${PREFIX}" --format "{{.Names}}")
        do
            echo "  server ${name}:5000;" >> nginx.conf
        done

        echo " }" >> nginx.conf
        echo " server { listen 80; location / { proxy_pass http://backend; } }" >> nginx.conf
        echo "}" >> nginx.conf

        docker cp nginx.conf $NGINX_CONTAINER:/etc/nginx/nginx.conf
        docker exec $NGINX_CONTAINER nginx -s reload
    fi

    sleep 8
done

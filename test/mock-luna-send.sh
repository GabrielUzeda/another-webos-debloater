#!/bin/sh
# test/mock-luna-send.sh - Mock para luna-send em testes offline

uri="$1"
payload="$2"

case "$uri" in
    *getForegroundAppInfo*)
        echo '{"returnValue":true,"appId":"com.webos.app.home","windowId":"","processId":"1234"}'
        ;;
    *getConfigs*)
        echo '{"returnValue":true,"configs":{"profile.blockedAppList":[]}}'
        ;;
    *getSystemSettings*)
        echo '{"returnValue":true,"settings":{"general":{"homePromotion":"on","sportsAlarm":"on"},"option":{"livePlus":"on"}}}'
        ;;
    *setConfigs*|*setPreloadPolicy*|*closeByAppId*|*blockSystemApp*|*releaseBlockSystemApp*|*setSystemSettings*|*launch*)
        echo '{"returnValue":true}'
        ;;
    *)
        echo '{"returnValue":true}'
        ;;
esac

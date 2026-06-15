if [ -n "$Description_DISPLAY_ID_ENV" ]
then
    python prepare_env.py
    if [ -e '.temp_env' ]
    then
        source .temp_env
        rm .temp_env
    else
        echo "[error] prepare env fail,can't find temp env setting file!"
        exit 1
    fi
else
    echo "[info] Description_DISPLAY_ID_ENV is not defined,skipping..."
fi

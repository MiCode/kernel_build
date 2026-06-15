import sys
import os
import json

if "Description_DISPLAY_ID_ENV" in os.environ:
    print "Description_DISPLAY_ID_ENV is defined!"
    version_string = os.getenv('Description_DISPLAY_ID_ENV')
    try:
        version_dict = json.loads(version_string)
    except:
        print "version_string is not a dict,exit"
        exit(0)
else:
    print "Description_DISPLAY_ID_ENV is not defined,exit!"
    exit(0)

filename = open('.temp_env','w')
for key in version_dict.keys():
    # os.environ[key] = version_dict[key]
    set_env_cmd = 'export' + ' ' + key.strip() + '_ENV'  + '=' + version_dict[key].strip() + '\n'
    print set_env_cmd,
    filename.write(set_env_cmd)


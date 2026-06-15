#!/bin/bash


#function cust_all_images()
#{
#    # gen crc list
#    local ver_dir=$1
#    echo "gen crc list......"
#    cd $ver_dir
#    python flash_gen_crc_list.py
#    rm -f flash_gen_crc_list.py
#    rm -f flash_gen_resparsecount
#}

function cust_all_sparse_images()
{
    local sparse_ver_dir=$1

    # delete the Redundant
    cd $sparse_ver_dir
    rm -f system.img vendor.img userdata.img cache.img

    rm -f rawprogram0.xml rawprogram0.xml.bak rawprogram0_upgrade.xml
    dd if=/dev/zero of=dummy.img bs=1024 count=8
    dd if=/dev/zero of=st1 bs=1024 count=1536
    dd if=/dev/zero of=st2 bs=1024 count=1536

    # backup rawprogram_unsparse.xml to rawprogram_unsparse_upgrade.xml and replace filename as "" for persist.img and fs_image.tar.gz.mbn.img
    rawprogram_unsparse="rawprogram_unsparse.xml"
    rawprogram_unsparse_upgrade="rawprogram_unsparse_upgrade.xml"
    if [ -e ${rawprogram_unsparse} ]; then
        cp ${rawprogram_unsparse} ${rawprogram_unsparse_upgrade}
        sed -i 's/fs_image.tar.gz.mbn.img//g' ${rawprogram_unsparse_upgrade}
        sed -i 's/persist.img//g' ${rawprogram_unsparse_upgrade}
        sed -i 's/filename="st1"/filename=""/g' ${rawprogram_unsparse_upgrade}
        sed -i 's/filename="st2"/filename=""/g' ${rawprogram_unsparse_upgrade}
        sed -i 's/filename="misc.img" label="misc"/filename="zeros_1sector.bin" label="misc"/g' ${rawprogram_unsparse_upgrade}
        sed -i 's/filename="zeros_1sector.bin" label="fsc"/filename="" label="fsc"/g' ${rawprogram_unsparse_upgrade}
        sed -i 's/filename="zeros_1sector.bin" label="DDR"/filename="" label="DDR"/g' ${rawprogram_unsparse_upgrade}
    fi

    rawprogram_unsparse_reset="rawprogram_unsparse_reset.xml"
    if [ -e ${rawprogram_unsparse} ]; then
    cp ${rawprogram_unsparse} ${rawprogram_unsparse_reset}
    sed -i 's/filename="" label="fsc"/filename="zeros_1sector.bin" label="fsc"/g' ${rawprogram_unsparse_reset}
    sed -i 's/filename="misc.img" label="misc"/filename="zeros_1sector.bin" label="misc"/g' ${rawprogram_unsparse_reset}
    #sed -i 's/filename="" label="cust"/filename="cust.img" label="cust"/g' ${rawprogram_unsparse_reset}
    #sed -i 's/\(label="cust".*\)\(sparse="true"\)/\1sparse="false"/g' ${rawprogram_unsparse_reset}
    fi

    # copy rawprogram_unsparse.xml to rawprogram0.xml which will be used by XI AN tools
    echo "copying rawprogram_unsparse.xml to rawprogram0.xml"
    cp $sparse_ver_dir/rawprogram_unsparse.xml $sparse_ver_dir/rawprogram0.xml
}



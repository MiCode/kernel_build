#!/bin/bash
ROOT_DIR=$(realpath $(dirname $(readlink -f $0))/../../..) #kernel_platform的绝对路径
#DTB_DIR="$ANDROID_PRODUCT_OUT/prebuilt_kernel/dtbs/"       #dtb和dtbo生成所在的目录
DTB_DIR="$1/prebuilt_kernel/dtbs/"       #dtb和dtbo生成所在的目录
DTB_PARSED_DIR="dtb_parsed"
NODE_INFO_FILE="node_info.txt"
STANDARD_NODE_FILE="$ROOT_DIR/qcom/proprietary/devicetree/reserved_memory_control/"$2"_standard_node_info.txt"  #standard_node_info.txt的绝对路径
DTC="${ROOT_DIR}/build/kernel/build-tools/path/linux-x86/dtc"
set -e

function dtb_parse () {
	local dts_name=""
	for i in $LIST_DTB
		do
			dts_name="${i%%.*}.dts"
			local dts_section=${i%%.*}
			#获取标准node list中的节点进行比对
			local node_check_list=$(sed -n "/<$dts_section>/,/<\/$dts_section>/p" $STANDARD_NODE_FILE) #找到标准node info文件中该dts所对应的块
			#echo "$node_check_list"
			${DTC} -I dtb -O dts $i -o "$DTB_PARSED_DIR/$dts_name"
			var=$(grep "/reserved-memory/" $DTB_PARSED_DIR/$dts_name | cut -d " " -f 3)
			for i in $var
		        do
		                local j=${i##*/}
				local node_name=${j%\"*} #节点名称
				#echo "$node_name"
				local length=$(echo -n $node_name|wc -c)
				local x=$(grep -A 10 "${node_name} {" $DTB_PARSED_DIR/$dts_name | grep -v "$node_name") #提取节点后的内容后10行
				local y=${x%%\}*} 	#不包含节点名称，提取节点内的内容
				if [ "$(echo $y|grep "size")" != "" ];then  #节点包含size属性
					local z=$(echo $y|grep -o "size = <.*>"|cut -d ";" -f 1|cut -d "=" -f 2|sed 's/^[ ]*//g') #截取size的值
					#将此处的node_name和size与标准的node list进行比对
					if [ "$(echo "$node_check_list"|grep "$node_name")" != "" ];then
						node_check_list_size=$(echo "$node_check_list"|grep "$node_name"|grep -o "size=<.*> "|cut -d "=" -f 2)
						#echo "node_check_list_size=====$node_check_list_size"
						#echo "z=======$z"
						if [ "$(echo "$node_check_list_size"|grep "$z")" == "" ];then  #如果size不匹配，则退出整个shell
							echo "error:please click the link  https://xiaomi.f.mioffice.cn/docs/dock4hbT8irwYSNeqXsKapTDI6b"
							echo "=================================="
							echo -e "$dts_name\nnode_name=$node_name\nstandard_size=$node_check_list_size\nmyself_size=$z"
							echo "=================================="
							exit 1
						fi
					else   #如果node_name不匹配，则退出
						echo "error:please click the link https://xiaomi.f.mioffice.cn/docs/dock4hbT8irwYSNeqXsKapTDI6b"
						echo "error:you should add your $dts_name:$node_name and size to file $STANDARD_NODE_FILE"
						exit 2
					fi
				elif [ "$(echo $y|grep "reg")" != "" ];then  #节点包含reg属性
					local z=$(echo $y|grep -o "reg = <.*>"|cut -d ";" -f 1|cut -d "=" -f 2) #截取reg的值
					#分割reg为address和size
					#reg_address=$(echo $z|awk '{print $1" "$2">"}')
					local reg_size=$(echo $z|awk '{print "<"$3" "$4}'|sed 's/^[ ]*//g')
					#将此处的node_name和size与标准的node list进行比对
					if [ "$(echo "$node_check_list"|grep "$node_name")" != "" ];then
						node_check_list_size=$(echo "$node_check_list"|grep "$node_name"|grep -o "size=<.*> "|cut -d "=" -f 2)   #提取比对表中的size比对
						#echo "node_check_list_size======$node_check_list_size"
						if [ "$(echo "$node_check_list_size"|grep "$reg_size")" == "" ];then  #如果size不匹配，则退出整个shell
							echo "error:please click the link  https://xiaomi.f.mioffice.cn/docs/dock4hbT8irwYSNeqXsKapTDI6b"
							echo "=================================="
						        echo -e "$dts_name\nnode_name=$node_name\nstandard_size=$node_check_list_size\nmyself_size=$reg_size"
							echo "=================================="
							exit 1
						fi
					else   #如果node_name不匹配，则退出
						echo "error:please click the link  https://xiaomi.f.mioffice.cn/docs/dock4hbT8irwYSNeqXsKapTDI6b"
						echo "error:you should add your $dts_name:$node_name and size to file $STANDARD_NODE_FILE"
						exit 2
					fi
				else  #既没有size属性也没有reg属性
					echo -e "=========="
				fi
        		done
		done

}

function dtbo_parse () {
	set -x
	local dts_name=""
	for i in $LIST_DTBO
		do
				dts_name="${i%%.*}.dts"
				set +e
				${DTC}  -I dtb -O dts $i -o "$DTB_PARSED_DIR/$dts_name"
				is_have_reserved_mem=$(grep "reserved_memory" "$DTB_PARSED_DIR/$dts_name")
				if [ -n "$is_have_reserved_mem" ];then
						dtbo_with_res_mem=${dtbo_with_res_mem}" "${dts_name}
				fi
				set -e
		done
	LIST_DTBO=${dtbo_with_res_mem}
	for j in $LIST_DTBO
	do
		#dts_name="${j%%.*}.dts"
		dts_name=${j}
		#dts_section=${j%%.*}  #每个dts中的section头部
		#${DTC} -I dtb -O dts $j -o "$DTB_PARSED_DIR/$dts_name"
		local head_info=$(sed -n "4,8p" $DTB_PARSED_DIR/$dts_name | sed "s/^\t//g" | sed "s/ //g" | grep -v "compatible" | grep -v "model") #每个dtbo的dts头部信息，只包含id信息
		head_info=$(echo $head_info)   #转换格式，不用行显示
		echo "head_info  :    $head_info"
		echo "================================================================="
		echo $(grep -inr "$head_info" $STANDARD_NODE_FILE)
		echo "================================================================="
		local node_check_list=$(sed -n "/<$head_info>/,/<\/$head_info>/p" $STANDARD_NODE_FILE) #找到标准node info文件中该dts所对应的块
		echo "node_check_list:"
		echo $node_check_list
		echo "================================================================="
		if [ -z "$node_check_list" ];then    #如果在标准node表中没有找到解析后的node，则退出
			echo "error:不存在 $dts_name,请在 $STANDARD_NODE_FILE 中添加信息"
			exit 3
		fi
		fragment_name=$(grep "reserved_memory" $DTB_PARSED_DIR/$dts_name|grep -o "fragment@[0-9]*")
		#is_have_reserved_mem=$(grep "reserved_memory" $DTB_PARSED_DIR/$dts_name)
		# if [ -z "$is_have_reserved_mem" ];then
			# echo "is_have_reserved_mem:"
			# echo $is_have_reserved_mem
			# echo "======================================================"
			# continue
		# else
			# fragment_name=$(echo "$is_have_reserved_mem" | grep -E -o "fragment@[0-9]*")
			# echo "fragment_name:"
			# echo $fragment_name
			# echo "======================================================"
		# fi
		if [ -n "$fragment_name" ];then  #找出有reserved_memory节点的dts
			for i in $fragment_name
				do
				#找出每个fragment中的子节点
				#找出所有节点及其属性的所有内容
				local str=$(sed -n "/${i} {/,/fragment/p" $DTB_PARSED_DIR/$dts_name | grep -E -v "(fragment|symbol|target|overlay|cells|ranges|};|-size|^$)")"{"
				#筛选出节点名称，组成一个整体,节点以"{"进行分割
				local node_name_group=$(echo "$str"|grep " {"|awk '{print$1}')
				#echo $node_name_group
				#local node_num=$(echo "$node_name_group"|wc -l)
					for i in $node_name_group  #i为每个node_name
						do
							local tmp=$(echo "$str"|sed -n "/${i}/,/{/p")
							#echo $tmp
							if [[ "$tmp" =~ "reg =" ]];then
								local reg=$(echo "$tmp"|grep -o "reg = <.*>"|cut -d ";" -f 1|cut -d "=" -f 2|sed 's/^[ ]*//g') #截取reg的值
								#reg_address=$(echo $z|awk '{print $1" "$2">"}')
								local reg_size=$(echo "$reg"|awk '{print "<"$3" "$4}')
								#将此处的node_name和size与标准的node list进行比对
								if [ "$(echo "$node_check_list"|grep "$i")" != "" ];then
									node_check_list_size=$(echo "$node_check_list"|grep "$i"|grep -o "size=<.*> "|cut -d "=" -f 2)   #提取比对表中的size比对
									if [ "$(echo "$node_check_list_size"|grep "$reg_size")" == "" ];then  #如果size不匹配，则退出整个shell
										echo "error:please click the link https://xiaomi.f.mioffice.cn/docs/dock4hbT8irwYSNeqXsKapTDI6b"
										echo "=================================="
										echo -e "$dts_name\nnode_name=$i\nstandard_size=$node_check_list_size\nmyself_size=$reg_size"
										echo "=================================="
										exit 1
									fi
								else   #如果node_name不匹配，则退出
									echo "error:please click the link https://xiaomi.f.mioffice.cn/docs/dock4hbT8irwYSNeqXsKapTDI6b"
									echo "error:you should add your $dts_name:$i and size to file $STANDARD_NODE_FILE"
									exit 2
								fi
							elif [[ "$tmp" =~ "size" ]];then
								local size=$(echo "$tmp"|grep -o "size = <.*>"|cut -d ";" -f 1|cut -d "=" -f 2|sed 's/^[ ]*//g')  #截取size的值
								if [ "$(echo "$node_check_list"|grep "$i")" != "" ];then
									node_check_list_size=$(echo "$node_check_list"|grep "$i"|grep -o "size=<.*> "|cut -d "=" -f 2)
									if [ "$(echo "$node_check_list_size"|grep "$size")" == "" ];then  #如果size不匹配，则退出整个shell
										echo "error:please click the link https://xiaomi.f.mioffice.cn/docs/dock4hbT8irwYSNeqXsKapTDI6b"
										echo "=================================="
										echo -e "$dts_name\nnode_name=$i\nstandard_size=$node_check_list_size\nmyself_size=$reg_size"
										echo "=================================="
										exit 1
									fi
								else   #如果node_name不匹配，则退出
									echo "error:please click the link https://xiaomi.f.mioffice.cn/docs/dock4hbT8irwYSNeqXsKapTDI6b"
									echo "error:you should add your $dts_name:$i and size to file $STANDARD_NODE_FILE"
									exit 2
								fi
							else   #节点中不存在size和reg属性，则忽略
								echo -e "==============="
							fi
						done
				done
		else
			echo "$dts_name have no fragment_name"
		fi
	done
}


#查看环境变量
echo "=========================================="
echo "DTB_DIR:${DTB_DIR}"
echo "STANDARD_INFO_FILE:${STANDARD_NODE_FILE}"
echo "ROOT_DIR:${ROOT_DIR}"
echo "ANDROID_KERNEL_OUT:${ANDROID_KERNEL_OUT}"
echo "ANDROID_BUILD_TOP:${ANDROID_BUILD_TOP}"
echo "TARGET_PRODUCT:${TARGET_PRODUCT}"
echo "\$1=PRODUCT_OUT:$1"         #core/Makefile传入变量PRODUCT_OUT
echo "TARGET_BOARD_PLATFORM:${TARGET_BOARD_PLATFORM}"
echo "\$2=TARGET_BOARD_PLATFORM:$2"   #core/Makefile中传入变量TARGET_BOARD_platform
echo "=========================================="

cd ${DTB_DIR}     #进入out/target/product/fuxi/prebuilt_kernel/dtbs/目录
LIST_DTB=$(ls | grep -v dtbo | grep .dtb)
echo "=========================================="
echo "$LIST_DTB"
echo "=========================================="

LIST_DTBO=$(ls | grep .dtbo)
echo "=========================================="
echo "$LIST_DTBO"
echo "=========================================="


if [ -d "$DTB_PARSED_DIR" ];then
	echo "=====================dtb_parsed directory exists====================="
	dtb_parse
	dtbo_parse
else
	echo "====================create dtb_parsed directory======================"
	mkdir dtb_parsed
	echo "====================create dtb_parsed directory done================="
	dtb_parse
	dtbo_parse
fi

echo "================================check reserved node done!==================================="

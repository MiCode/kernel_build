#!/bin/bash

#用于生成最新的standard_node_info.txt
#该文件放在kernel_platform/build/kernel/android/下

######################注意事项##########################
#1.执行本脚本之前，需要先初始化环境变量以及lunch，并且执行prepare_vendor.sh
#2.本脚本只能在当前路径下使用，不可移动到别处使用
#3.生成的文件为对应平台的node_info.txt,与本脚本同一路径下

ROOT_DIR=$(realpath $(dirname $(readlink -f $0))/../../..) #kernel_platform目录的绝对路径
#DTB_DIR="$ANDROID_PRODUCT_OUT/prebuilt_kernel/dtbs/"       #dtb和dtbo生成所在的目录
DTB_DIR="$ANDROID_PRODUCT_OUT/prebuilt_kernel/dtbs"       #dtb和dtbo生成所在的目录
DTB_PARSED_DIR="$DTB_DIR/dtb_parsed"
NODE_INFO_FILE=$DTB_DIR/"${TARGET_BOARD_PLATFORM}_standard_node_info.txt"    #standard_node_info生成在OUT下

LIST_DTB=$(ls $DTB_DIR | grep -v dtbo | grep .dtb)
LIST_DTBO=$(ls $DTB_DIR | grep .dtbo)
DTC="$ROOT_DIR/build/kernel/build-tools/path/linux-x86/dtc"     #该dtc工具是代码中的dtc，如果本地代码不全可以使用外部的dtc工具，一样的效果

#dtb的生成名称是直接从从源文件名称复制过来的
function dtb_parse () {
	local dts_name=""
	for i in $LIST_DTB
		do
			dts_name="${i%%.*}.dts"
			${DTC} -I dtb -O dts $DTB_DIR/$i -o "$DTB_PARSED_DIR/$dts_name"
			echo -e "\t<${dts_name%%.*}>">>$NODE_INFO_FILE
			var=$(grep "/reserved-memory/" $DTB_PARSED_DIR/$dts_name | cut -d " " -f 3)
			for i in $var
		        do
		                local j=${i##*/}
				local node_name=${j%\"*} #节点名称
				local length=$(echo -n $node_name|wc -c)
				local x=$(grep -A 10 "${node_name} {" $DTB_PARSED_DIR/$dts_name | grep -v "$node_name") #提取节点后的内容后10行
				local y=${x%%\}*} 	#不包含节点名称，提取节点内的内容
				if [ "$(echo $y|grep "size")" != "" ];then
					#local z=$(echo $y|grep -o "size = <.*>"|cut -d ";" -f 1|cut -d "=" -f 2|sed 's/^[ ]*//g') #截取size的值
					local z=$(echo $y|grep -o "size = <.*>"|cut -d ";" -f 1|cut -d "=" -f 2|sed 's/^[ ]*//g') #截取size的值
					echo -e "\t\t< node_name=$node_name size=$z >">>$NODE_INFO_FILE
				elif [ "$(echo $y|grep "reg")" != "" ];then
					local z=$(echo $y|grep -o "reg = <.*>"|cut -d ";" -f 1|cut -d "=" -f 2) #截取reg的值
					#分割reg为address和size
					#reg_address=$(echo $z|awk '{print $1" "$2">"}')
					local reg_size=$(echo $z|awk '{print "<"$3" "$4}'|sed 's/^[ ]*//g')
					echo -e "\t\t< node_name=$node_name size=$reg_size >">>$NODE_INFO_FILE
				else
					echo -e "\t\t< node_name=$node_name size=<none> >">>$NODE_INFO_FILE
				fi
        		done
			echo -e "\t</${dts_name%%.*}>\n">>$NODE_INFO_FILE
		done

}

#dtbo的生成的名称是由多个文件拼接而成，而拼接规律暂时没有找到
function dtbo_parse () {
	local dts_name=""
	local head_info=""
	local log_tail="=============================================="
	for j in $LIST_DTBO
	do
		dts_name="${j%%.*}.dts"
		${DTC} -I dtb -O dts $DTB_DIR/$j -o "$DTB_PARSED_DIR/$dts_name"    #反编译dtbo，反编译的生成名字与原dtbo名字相同
		local log_head="==================$DTB_PARSED_DIR/$dts_name=================="
		head_info=$(sed -n "4,8p" $DTB_PARSED_DIR/$dts_name | sed "s/^\t//g" | sed "s/ //g" | grep -v "compatible" | grep -v "model") #每个dtbo的dts头部信息，包含model,id,不包含compatible
		log_full=${log_head}"\n"$(echo $head_info)"\n"${log_tail}"\n"     #log_full由dtbo的名称+head_info+log+tail
		log=${log}${log_full}     #dtbo的所有信息集合
		echo -e "\t<${dts_name%%.*}>">>$NODE_INFO_FILE
		echo -e "\t<$(echo $head_info)>">>$NODE_INFO_FILE
		fragment_name=$(grep "reserved_memory" $DTB_PARSED_DIR/$dts_name|grep -o "fragment@[0-9]*")

		for i in $fragment_name
			do
			#找出每个fragment中的子节点
			#str1=$(sed -n "/${i} {/,/fragment/p" dtb_parsed/fuxi-sm8550-overlay.dts | grep -E -v "(fragment|symbol|target|overlay|cells|ranges|};|-size|^$)"| grep "{"|awk '{print$1}')
			#找出所有节点及其属性的所有内容
			local str=$(sed -n "/${i} {/,/fragment/p" $DTB_PARSED_DIR/$dts_name | grep -E -v "(fragment|symbol|target|overlay|cells|ranges|};|-size|^$)")"{"
			#echo "$str"
			#筛选出节点名称，组成一个整体
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
							#echo "node_name = $i      size  =  $reg_size"
							echo -e "\t\t< node_name=$i size=$reg_size >">>$NODE_INFO_FILE
						elif [[ "$tmp" =~ "size" ]];then
							local size=$(echo "$tmp"|grep -o "size = <.*>"|cut -d ";" -f 1|cut -d "=" -f 2|sed 's/^[ ]*//g')  #截取size的值
							echo -e "\t\t< node_name=$i size=$size >">>$NODE_INFO_FILE
						else
							echo -e "\t\t< node_name=$i size=<none> >">>$NODE_INFO_FILE
					fi
				done
			done
		echo -e "\t</$(echo $head_info)>">>$NODE_INFO_FILE
		echo -e "\t</${dts_name%%.*}>\n">>$NODE_INFO_FILE
	done
	#echo -e "$log"
}


#将平台名称转换成大写
platform=$(echo "$TARGET_BOARD_PLATFORM" | tr 'a-z' 'A-Z' )

#打印环境变量
echo "==============================打印变量==================================="
echo "TARGET_BOARD_PLATFORM:$TARGET_BOARD_PLATFORM"   #打印平台信息
echo "OUT:$OUT"
echo "ANDROID_PRODUCT_OUT:$ANDROID_PRODUCT_OUT"
echo "DTB_DIR:$DTB_DIR"
echo "DTB_PARSED_DIR:$DTB_PARSED_DIR"
echo "NODE_INFO_FILE:$NDOE_INFO_FILE"
echo "DTC:$DTC"
echo "platform:$platform"

#创建node_info.txt
if [ ! -e $NODE_INFO_FILE ];then
	echo "====================creating node_info.txt=================== "
	touch $NODE_INFO_FILE
	echo "====================creating node_info.txt success==========="
else
	echo -n  "">$NODE_INFO_FILE     #如果存在该文件，清空文件
	echo "=====================node_info.txt exists====================="
fi


if [ ! -d "$DTB_PARSED_DIR" ];then
	mkdir  $DTB_PARSED_DIR
fi

echo "<${platform}_PLATFORM>">>$NODE_INFO_FILE
dtb_parse
dtbo_parse
echo "</${platform}_PLATFORM>">>$NODE_INFO_FILE

if [ ! -d  reserved_memory_control ];then
    mkdir reserved_memory_control
fi

cp $NODE_INFO_FILE $ROOT_DIR/build/kernel/android/reserved_memory_control/
echo "==============================done==================================="


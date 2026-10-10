from src.sec_class_define import data_desc
from src.sec_fifo import sec_fifo


# 加载并拆包数据  
# 源数据包分成4部分， --4--，---2---，-------1--------，--3--，
# 其中：4：NAS时 mac位置， 3：AS时mac位置， 故3,4 不会并存， 
#       1：proc_len, 加密或者move的数据，   2：pre_aad_len, 只做完保的数据， 实际上做完保hdr+pre_aad_len+proc_len

def load_and_dispatch_packet(i_packet_len,i_packet_data,i_packet_seg_num,i_pre_aad_len,i_pre_aad_in_byte_offset,i_proc_len,i_mac_load_byte_offset,i_mac_len,i_mac_append,i_mac_load_en,i_mac_enc):
    # 输入为从 tv load 进来的数据，有一段或者多段；
    # 分析输出
    # 源数据包分成4部分， --notuse--,--4--，---2---，-------1--------，--3--，
    # 两种情况： 1. i_mac_append = 0， mac在数据包中间， 此时数据包结构： --notuse--,--4--，---2---，-------1--------，
    #           2. i_mac_append = 1， mac在数据包中间， 此时数据包结构： --notuse--,---2---，-------1--------，--3--，
    # 
    bytes_out_data_list = []
    drop_1st = True
    #2bit 0:enc,1:int,2:int2enc,3:enc2int,4:null
    # not use & nas mac
    if i_mac_load_en and not i_mac_append: #nas deint
        bytes_out_data_list.append(i_mac_load_byte_offset)
        bytes_out_data_list.append(i_mac_len)
    else: 
        bytes_out_data_list.append(i_pre_aad_in_byte_offset)
    # pre aad
    bytes_out_data_list.append(i_pre_aad_len)
    # proc
    bytes_out_data_list.append(i_proc_len)
    # as mac
    if i_mac_load_en and i_mac_append and (not i_mac_enc):
        bytes_out_data_list.append(i_mac_len)

    # check data len
    total_len = 0
    for i in range(len(bytes_out_data_list)):
        total_len += bytes_out_data_list[i]
    if i_packet_len != total_len:
        print("Cheak data failed!")

    load_data_fifo = sec_fifo(64)
    write_delay = 0.02
    read_delay = 0.05
    out_data_channel_num = len(bytes_out_data_list)
    o_data = load_data_fifo.run(i_packet_data,i_packet_seg_num,write_delay,bytes_out_data_list,out_data_channel_num,drop_1st,read_delay)

    # out
    o_mac_data = data_desc([],[],[],0)
    if i_mac_load_en and not i_mac_enc:
    #deint, 特殊的 as dec + deint, mac在解密之后才提取, mac包含在了 proc_data中，走else分支
        if i_mac_append:  #as deint
            o_pre_aad_data = o_data[0]
            o_proc_data = o_data[1]
            o_mac_data = o_data[2]
        else:  # nas
            o_mac_data = o_data[0]
            o_pre_aad_data = o_data[1]
            o_proc_data = o_data[2]
    else:
        o_pre_aad_data = o_data[0]
        o_proc_data = o_data[1]
    return o_pre_aad_data,o_proc_data,o_mac_data


if __name__ == "__main__":
    #input
    i_pre_aad_len = 0
    i_pre_aad_in_byte_offset = 0
    i_proc_len = 0
    i_proc_in_byte_offset = 0
    i_mac_len = 4
    i_mac_in_byte_offset = 0
    i_mac_append = 0

    i_packet_len = []  # 一维数据，每段长度
    i_packet_data = []  # 二维数据， 数据会分段加载
    i_packet_seg_num = 0

    o_pre_aad_data = data_desc()
    o_proc_data = data_desc()
    o_mac_data = data_desc()
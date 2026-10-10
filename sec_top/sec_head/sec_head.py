from src.sec_class_define import data_desc

def gen_hdr_data(i_head_start,i_is_sdap_hdr_exist,i_pdcp_sn_bit_size,i_rb_type,i_pdcp_sn,i_sdap_hdr,head:data_desc):
    hdr = 0
    len = 0
    if i_head_start and i_is_sdap_hdr_exist:
        match (i_pdcp_sn_bit_size):
            case 5:
                hdr = i_rb_type << 31 | 0x0 << 29 | (i_pdcp_sn & 0x1F) << 24 | i_sdap_hdr << 16 | 0x0
                len = 2
            case 7:
                hdr = i_rb_type << 31 | (i_pdcp_sn & 0x7F) << 24 | i_sdap_hdr << 16 | 0x0
                len = 2
            case 12:
                hdr = i_rb_type << 31 | 0x0 << 28 | (i_pdcp_sn & 0xFFF) << 16 | i_sdap_hdr << 8 | 0x0
                len = 3
            case 18:
                hdr = 0x20 << 26 | (i_pdcp_sn & 0x3FFFF) << 8 | i_sdap_hdr
                len = 4
    elif i_head_start:
        match (i_pdcp_sn_bit_size):
            case 5:
                hdr = i_rb_type << 31 | 0x0 << 29 | (i_pdcp_sn & 0x1F) << 24 | 0x0
                len = 1
            case 7:
                hdr = i_rb_type << 31 | (i_pdcp_sn & 0x7F) << 24 | 0x0
                len = 1
            case 12:
                hdr = i_rb_type << 31 | 0x0 << 28 | (i_pdcp_sn & 0xFFF) << 16 | 0x0
                len = 2
            case 18:
                hdr = 0x20 << 26 | (i_pdcp_sn & 0x3FFFF) << 8 | 0x0
                len = 3
    head.data.append(hdr)
    head.data_vld = [1]
    head.data_len = len
    head.last = [1]
    return head

if __name__ == "__main__":
    #input
    i_head_start = 0

    i_is_sdap_hdr_exist = 0
    i_sdap_hdr = 0 #8-width
    i_rb_type = 0
    i_pdcp_sn = 0 #18-width
    i_pdcp_sn_bit_size = 0 #5-width

    o_hdr_data = 0 # data_desc
    o_hdr_done  = 0 




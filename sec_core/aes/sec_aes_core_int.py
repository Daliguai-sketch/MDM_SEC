# ==================== S盒 ====================
SBOX = [
    0x63,0x7C,0x77,0x7B,0xF2,0x6B,0x6F,0xC5,0x30,0x01,0x67,0x2B,0xFE,0xD7,0xAB,0x76,
    0xCA,0x82,0xC9,0x7D,0xFA,0x59,0x47,0xF0,0xAD,0xD4,0xA2,0xAF,0x9C,0xA4,0x72,0xC0,
    0xB7,0xFD,0x93,0x26,0x36,0x3F,0xF7,0xCC,0x34,0xA5,0xE5,0xF1,0x71,0xD8,0x31,0x15,
    0x04,0xC7,0x23,0xC3,0x18,0x96,0x05,0x9A,0x07,0x12,0x80,0xE2,0xEB,0x27,0xB2,0x75,
    0x09,0x83,0x2C,0x1A,0x1B,0x6E,0x5A,0xA0,0x52,0x3B,0xD6,0xB3,0x29,0xE3,0x2F,0x84,
    0x53,0xD1,0x00,0xED,0x20,0xFC,0xB1,0x5B,0x6A,0xCB,0xBE,0x39,0x4A,0x4C,0x58,0xCF,
    0xD0,0xEF,0xAA,0xFB,0x43,0x4D,0x33,0x85,0x45,0xF9,0x02,0x7F,0x50,0x3C,0x9F,0xA8,
    0x51,0xA3,0x40,0x8F,0x92,0x9D,0x38,0xF5,0xBC,0xB6,0xDA,0x21,0x10,0xFF,0xF3,0xD2,
    0xCD,0x0C,0x13,0xEC,0x5F,0x97,0x44,0x17,0xC4,0xA7,0x7E,0x3D,0x64,0x5D,0x19,0x73,
    0x60,0x81,0x4F,0xDC,0x22,0x2A,0x90,0x88,0x46,0xEE,0xB8,0x14,0xDE,0x5E,0x0B,0xDB,
    0xE0,0x32,0x3A,0x0A,0x49,0x06,0x24,0x5C,0xC2,0xD3,0xAC,0x62,0x91,0x95,0xE4,0x79,
    0xE7,0xC8,0x37,0x6D,0x8D,0xD5,0x4E,0xA9,0x6C,0x56,0xF4,0xEA,0x65,0x7A,0xAE,0x08,
    0xBA,0x78,0x25,0x2E,0x1C,0xA6,0xB4,0xC6,0xE8,0xDD,0x74,0x1F,0x4B,0xBD,0x8B,0x8A,
    0x70,0x3E,0xB5,0x66,0x48,0x03,0xF6,0x0E,0x61,0x35,0x57,0xB9,0x86,0xC1,0x1D,0x9E,
    0xE1,0xF8,0x98,0x11,0x69,0xD9,0x8E,0x94,0x9B,0x1E,0x87,0xE9,0xCE,0x55,0x28,0xDF,
    0x8C,0xA1,0x89,0x0D,0xBF,0xE6,0x42,0x68,0x41,0x99,0x2D,0x0F,0xB0,0x54,0xBB,0x16
]

# ==================== GF(2^8) 乘法 ====================
def xtime(x):
    return ((x << 1) ^ 0x1B) & 0xFF if (x & 0x80) else (x << 1) & 0xFF

def gf_mul(x, y):
    res = 0
    while y:
        if y & 1:
            res ^= x
        x = xtime(x)
        y >>= 1
    return res

# ==================== 轮常量 ====================
RCON = [
    0x00000000,
    0x01000000,0x02000000,0x04000000,0x08000000,
    0x10000000,0x20000000,0x40000000,0x80000000,
    0x1B000000,0x36000000
]

# ==================== 字节 <-> 32位字 ====================
def bytes2words(b):
    word = 0
    for i in range(len(b)):
        word |= b[i] << (4-1-i)*8
    return word

def words2bytes(word):
    b = []
    b.extend([(word>>24)&0xFF,(word>>16)&0xFF,(word>>8)&0xFF,word&0xFF])
    return b

# ====================words2bytes[] 密钥扩展 ====================
def sub_word(w):
    return (SBOX[(w>>24)&0xFF]<<24) | (SBOX[(w>>16)&0xFF]<<16) | \
           (SBOX[(w>>8)&0xFF]<<8) | SBOX[w&0xFF]

def rot_word(w):
    # w: 4*1
    return ((w << 8) | (w >> 24)) & 0xFFFFFFFF

def matrix_inv(w):
    transposed = list(zip(*w))
    return transposed

def convert_col_row(w):
    conver_w = [[0 for _ in range(4)] for _ in range(4)]
    for i in range(4):
        conver_w[0][i] = w[i][0]
        conver_w[1][i] = w[i][1]
        conver_w[2][i] = w[i][2]
        conver_w[3][i] = w[i][3]
    return conver_w

# Nk: 密钥长度，单位是word， Nr：轮数
# return w_bytes = [[byte_0,byte_1,byte_2,byte_3],[byte_0,byte_1,byte_2,byte_3],[],]
def key_expansion(key, Nk=4, Nr=10):
    Nb = 4
    w = []
    num_w = (Nr + 1) * Nb
    i = Nk
    w.extend(key)
    while i < num_w:
        wi_1 = w[i-1]
        wi_4 = w[i-Nk]
        if i % Nk == 0:
            wi_1 = sub_word(rot_word(wi_1)) ^ RCON[i//Nk]
        wi = wi_4 ^ wi_1
        w.append(wi)
        i += 1

    w_byte = []
    for i in range(len(w)):
        w_byte.append(words2bytes(w[i]))
    return w_byte

# ==================== AES 轮函数 ====================
def add_round_key(state, key):
    for i in range(4):
        for j in range(4):
            state[i][j] ^= key[i][j]&0xFF

def sub_bytes(state):
    for r in range(4):
        for c in range(4):
            state[r][c] = SBOX[state[r][c]]

def shift_rows(state):
    # row 1: shift 1
    state[1][0], state[1][1], state[1][2], state[1][3] = \
        state[1][1], state[1][2], state[1][3], state[1][0]
    # row 2: shift 2
    state[2][0], state[2][1], state[2][2], state[2][3] = \
        state[2][2], state[2][3], state[2][0], state[2][1]
    # row 3: shift 3
    state[3][0], state[3][1], state[3][2], state[3][3] = \
        state[3][3], state[3][0], state[3][1], state[3][2]
    
def mix_columns(state):
    for c in range(4):
        s0 = state[0][c]
        s1 = state[1][c]
        s2 = state[2][c]
        s3 = state[3][c]
        state[0][c] = xtime(s0) ^ xtime(s1) ^ s1 ^ s2 ^ s3
        state[1][c] = s0 ^ xtime(s1) ^ xtime(s2) ^ s2 ^ s3
        state[2][c] = s0 ^ s1 ^ xtime(s2) ^ xtime(s3) ^ s3
        state[3][c] = xtime(s0) ^ s0 ^ s1 ^ s2 ^ xtime(s3)

# state: always 4*4byte
def aes_core_first_round(state,w):
    ret = []
    for i in range(4): 
        tmp = []
        for j in range(4):
            tmp.append(state[i][j] ^ w[i][j])
        ret.append(tmp)
    return ret

def aes_core_middle_round(state,w,Nk=4,Nr=10):
    round_num = Nr - 1
    for i in range(round_num):
        key = w[Nk*(i+1):Nk*(i+1)+4] # 4*4byte
        state = convert_col_row(state)
        sub_bytes(state)
        shift_rows(state)
        mix_columns(state)
        state = convert_col_row(state)
        add_round_key(state,key)
    return state

def aes_core_last_round(state,w):
    key = w[-4:]
    state = convert_col_row(state)
    sub_bytes(state)
    shift_rows(state),
    state = convert_col_row(state)
    add_round_key(state,key)
    return state

def aes_int_key_exp(key,Nk=4,Nr=10):
    k = []
    # 初始密钥按照列优先填入二维数组, 4列,Nk行   
    for i in range(Nk):
        k.append(key[Nk-1-i])
    w = key_expansion(k,Nk,Nr)
    return w

# msg/stream: List-4 words
def aes_int_core(msg,w,Nk=4,Nr=10):
    state = []
    stream = []
    for i in range(4):
        state.append(words2bytes(msg[i]))
    state = aes_core_first_round(state,w)
    state = aes_core_middle_round(state,w,Nk,Nr)
    state = aes_core_last_round(state,w)
    for i in range(4):
        stream.append(bytes2words(state[i]))
    return stream



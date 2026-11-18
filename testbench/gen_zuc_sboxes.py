from pathlib import Path

from sec_core.zuc import sec_zuc_core as zuc


OUT_DIR = Path("rtl/zuc")
OUT_DIR.mkdir(parents=True, exist_ok=True)


def generate_sbox(module_name, table):

    if len(table) != 256:
        raise ValueError(
            f"{module_name}: expected 256 entries"
        )

    lines = []

    lines.append(
        f"module {module_name} ("
    )

    lines.append(
        "    input  wire [7:0] i_data,"
    )

    lines.append(
        "    output reg  [7:0] o_data"
    )

    lines.append(
        ");"
    )

    lines.append("")

    lines.append(
        "always @(*) begin"
    )

    lines.append(
        "    case (i_data)"
    )

    for index, value in enumerate(table):

        lines.append(
            f"        8'h{index:02X}: "
            f"o_data = 8'h{value:02X};"
        )

    lines.append(
        "        default: o_data = 8'h00;"
    )

    lines.append(
        "    endcase"
    )

    lines.append(
        "end"
    )

    lines.append("")

    lines.append("endmodule")

    output = OUT_DIR / f"{module_name}.v"

    output.write_text(
        "\n".join(lines) + "\n",
        encoding="utf-8"
    )

    print(f"Generated: {output}")

def main():
    generate_sbox(
        "zuc_sbox_s0",
        zuc.S0
    )

    generate_sbox(
        "zuc_sbox_s1",
        zuc.S1
    )
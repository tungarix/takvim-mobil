# Resmi tatil tablosunu (araştırma çıktısı JSON) gömülü Dart verisine çevirir; tabloyu elle yazma.
# Kullanım: python tool/resmi_tatil_uret.py <resmi-tatiller.json>
import json, sys

d = json.load(open(sys.argv[1], encoding="utf8"))
satirlar = []
for g in d["gunler"]:
    ad = g["ad_tr"].replace(chr(92), chr(92) * 2).replace("'", chr(92) + "'")
    satirlar.append("  ('%s', '%s', %s, %s)," % (g["tarih"], ad, str(g["yarim_gun"]).lower(), str(g["tur"] == "dini").lower()))
cikti = (
    "// ÜRETİLDİ: tool/resmi_tatil_uret.py (elle düzenleme). Kaynak ve notlar:\n"
    + "".join("// %s\n" % n for n in [d["notlar"]] + d["kaynaklar"])
    + "// (tarih, ad, yarım gün, dini)\n"
    + "const resmiTatilVerisi = <(String, String, bool, bool)>[\n"
    + "\n".join(satirlar)
    + "\n];\n"
)
open("lib/core/resmi_tatil_veri.dart", "w", encoding="utf8", newline="\n").write(cikti)

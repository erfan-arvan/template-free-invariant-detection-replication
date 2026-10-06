import pathlib
p = pathlib.Path("java/daikon/chicory/DTraceWriter.java")
content = p.read_text()
old = """    if (curInfo.dTraceShouldPrint()) {
      if (!(curInfo instanceof StaticObjInfo)) {
        outFile.println(curInfo.getName());
        outFile.println(curInfo.getDTraceValueString(val));
      }"""
new = """    if (curInfo.dTraceShouldPrint()) {
      if (!(curInfo instanceof StaticObjInfo)) {
        outFile.println(curInfo.getName());
        String valueString;
        try {
          valueString = curInfo.getDTraceValueString(val);
        } catch (Throwable t) {
          valueString = "nonsensical" + DaikonWriter.lineSep + "2";
        }
        outFile.println(valueString);
      }"""
assert content.count(old) == 1, f"expected exactly one match, found {content.count(old)}"
p.write_text(content.replace(old, new))
print("Patched java/daikon/chicory/DTraceWriter.java")

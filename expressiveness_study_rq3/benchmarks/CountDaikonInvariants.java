import daikon.FileIO;
import daikon.PptMap;
import daikon.PptTopLevel;
import daikon.inv.Invariant;
import java.io.File;

public class CountDaikonInvariants {
    public static void main(String[] args) throws Exception {
        if (args.length != 1) {
            throw new IllegalArgumentException("Expected one .inv.gz path");
        }

        PptMap map = FileIO.read_serialized_pptmap(new File(args[0]), true);
        long entry = 0;
        long exit = 0;
        long entryPoints = 0;
        long exitPoints = 0;

        for (PptTopLevel ppt : map.all_ppts()) {
            String name = ppt.name();
            boolean isEntry = name.endsWith(":::ENTER");
            boolean isExit = name.matches(".*:::EXIT[0-9]*");
            if (!isEntry && !isExit) {
                continue;
            }

            if (isEntry) {
                entryPoints++;
            } else {
                exitPoints++;
            }

            for (Invariant inv : ppt.getInvariants()) {
                if (inv.isWorthPrinting()) {
                    if (isEntry) {
                        entry++;
                    } else {
                        exit++;
                    }
                }
            }
        }

        System.out.printf(
            "FILE=%s ENTRY=%d ENTRY_PPTS=%d EXIT=%d EXIT_PPTS=%d N_D=%d%n",
            args[0], entry, entryPoints, exit, exitPoints, entry + exit
        );
    }
}

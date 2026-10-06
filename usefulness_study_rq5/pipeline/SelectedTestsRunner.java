import java.util.ArrayList;
import java.util.Arrays;
import java.util.HashSet;
import java.util.List;
import java.util.Set;
import org.junit.runner.Description;
import org.junit.runner.JUnitCore;
import org.junit.runner.Request;
import org.junit.runner.Result;
import org.junit.runner.manipulation.Filter;
import org.junit.runner.notification.Failure;

public class SelectedTestsRunner {

  static Filter methods(final Set<String> names, final boolean exclude) {
    return new Filter() {
      @Override
      public boolean shouldRun(Description d) {
        if (!d.isTest()) {
          return true;
        }
        return names.contains(d.getMethodName()) != exclude;
      }

      @Override
      public String describe() {
        return (exclude ? "exclude " : "only ") + names;
      }
    };
  }

  public static void main(String[] args) throws Exception {
    JUnitCore core = new JUnitCore();
    int total = 0;
    int failures = 0;
    for (String spec : args) {
      String[] parts = spec.split("::", 2);
      Class<?> cls = Class.forName(parts[0]);
      Request request = Request.aClass(cls);
      if (parts.length == 2) {
        boolean exclude = parts[1].startsWith("!");
        List<String> names = new ArrayList<>();
        for (String m : parts[1].split(",")) {
          names.add(m.startsWith("!") ? m.substring(1) : m);
        }
        request = request.filterWith(methods(new HashSet<>(names), exclude));
      }
      Result r = core.run(request);
      total += r.getRunCount();
      failures += r.getFailureCount();
      for (Failure f : r.getFailures()) {
        System.out.println("[SelectedTestsRunner] FAIL " + f.getDescription());
      }
    }
    System.out.println("[SelectedTestsRunner] total=" + total + " failures=" + failures);
    System.exit(0);
  }
}

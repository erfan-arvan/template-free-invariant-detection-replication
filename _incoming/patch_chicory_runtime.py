import pathlib
p = pathlib.Path("java/daikon/chicory/Runtime.java")
content = p.read_text()
old = """      if (debug) {
        System.out.println("processing class " + class_info.class_name);
      }
      if (first_class) {
        decl_writer.printHeaderInfo(class_info.class_name);
        first_class = false;
      }
      class_info.initViaReflection();
      // class_info.dump (System.out);

      // Create tree structure for all method entries/exits in the class
      for (MethodInfo mi : class_info.method_infos) {
        mi.traversalEnter = RootInfo.enter_process(mi, Runtime.nesting_depth);
        mi.traversalExit = RootInfo.exit_process(mi, Runtime.nesting_depth);
      }

      decl_writer.printDeclClass(class_info, comp_info);
    }
  }"""
new = """      if (debug) {
        System.out.println("processing class " + class_info.class_name);
      }
      if (first_class) {
        decl_writer.printHeaderInfo(class_info.class_name);
        first_class = false;
      }
      try {
        class_info.initViaReflection();
        // class_info.dump (System.out);

        // Create tree structure for all method entries/exits in the class
        for (MethodInfo mi : class_info.method_infos) {
          mi.traversalEnter = RootInfo.enter_process(mi, Runtime.nesting_depth);
          mi.traversalExit = RootInfo.exit_process(mi, Runtime.nesting_depth);
        }

        decl_writer.printDeclClass(class_info, comp_info);
      } catch (Throwable t) {
        System.err.println(
            "Warning: Chicory failed to process class "
                + class_info.class_name
                + ", skipping it: "
                + t);
      }
    }
  }"""
assert content.count(old) == 1, f"expected exactly one match, found {content.count(old)}"
p.write_text(content.replace(old, new))
print("Patched java/daikon/chicory/Runtime.java")

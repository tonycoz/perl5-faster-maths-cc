// an attempt to reproduce the problem I had using concepts
// and an anonymous namespace
// I didn't manage it
#include <vector>
#include <string>
#include <variant>
#include <sstream>
#include <iostream>
#include <tuple>

#ifdef USE_STATIC
#define MYSTATIC static
#else
#define MYSTATIC
#endif

#ifndef USE_STATIC
namespace {
#endif

  struct One {
  };
  struct Two {
  };
  using OneOrTwo = std::variant<One, Two>;
  using Stack = std::vector<OneOrTwo>;
  MYSTATIC std::ostream &
  operator <<(std::ostream &out, const One &one) {
    out << "One";
    return out;
  }
  MYSTATIC std::ostream &
  operator <<(std::ostream &out, const Two &one) {
    out << "Two";
    return out;
  }
  MYSTATIC std::ostream &
  operator <<(std::ostream &out, const OneOrTwo &oot) {
    std::visit([&](const auto &thing) { out << thing; }, oot);
    return out;
  }
  MYSTATIC std::ostream &
  operator <<(std::ostream &out, const Stack &st) {
    for (auto i : st) {
      out << i << ' ';
    }
    return out;
  }

  struct Container {
    std::ostringstream s;
  };
  template <typename T>
  concept Insertable = requires (T a) {
    { std::cout << a }->std::convertible_to<std::ostream &>;
  };

  template <Insertable Val>
  Container &
  operator <<(Container &c, const Val &v) {
    c.s << v;
    //if (DebugFlags(CCDebugFlags::DumpCode))
      std::cerr << v;
    return c;
  }

  void f() {
    Stack s;
    Container c;
    c << s << '\n';
  }
  
#ifndef USE_STATIC
}
#endif


  

#pragma once

template <typename BitType>
class BitSet {
  unsigned m_bits = 0;
 public:
  BitSet &
  operator |=(const BitSet &b) {
    m_bits |= b.m_bits;
    return *this;
  }
  BitSet &
  operator |=(const BitType b) {
    m_bits |= (unsigned)b;
    return *this;
  }
  bool
  operator()(BitType bit) const {
    return (unsigned)m_bits & (unsigned)bit;
  }
};

// helper for visiting
template<class... Ts>
struct overloaded : Ts... { using Ts::operator()...; };
// explicit deduction guide (not needed as of C++20)
template<class... Ts>
overloaded(Ts...) -> overloaded<Ts...>;


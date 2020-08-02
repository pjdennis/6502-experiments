#include <iostream>

int main() {

  std::cout << "Hello!\n";

  char c;
  std::cin >> c;

  std::cout << "Value:[" << static_cast<int>(c) << "]\n";
  
}

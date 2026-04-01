struct Box {
  Box();
  int x;
};

Box::Box() : x(17) {}

extern const Box box = Box();

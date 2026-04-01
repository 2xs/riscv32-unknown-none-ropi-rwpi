struct Box {
  Box();
  int x;
};

extern const Box box;

const Box *get_box_addr() {
  return &box;
}

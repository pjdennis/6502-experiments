;;; 'main { }'
(program
  (address $4000)
  (output raw)
  (target wendy2c)
  (imports)
  (vars)
  (enums)
  (structs)
  (subs
    (subdef main main void
      (params)
      (block))))

;;; 'main { txt.print("hi") }'
(program
  (address $4000)
  (output raw)
  (target wendy2c)
  (imports)
  (vars)
  (enums)
  (structs)
  (subs
    (subdef main main void
      (params)
      (block
        (exprstmt
          (call txt.print
            (str "hi")))))))

;;; 'ubyte x\nmain { x = 1 x += 2 x <<= 1 }'
(program
  (address $4000)
  (output raw)
  (target wendy2c)
  (imports)
  (vars
    (var ubyte x))
  (enums)
  (structs)
  (subs
    (subdef main main void
      (params)
      (block
        (assign =
          (id x)
          (int 1))
        (assign +=
          (id x)
          (int 2))
        (assign <<=
          (id x)
          (int 1))))))

;;; 'ubyte x\nmain { if x == 0 { x = 1 } }'
(program
  (address $4000)
  (output raw)
  (target wendy2c)
  (imports)
  (vars
    (var ubyte x))
  (enums)
  (structs)
  (subs
    (subdef main main void
      (params)
      (block
        (if
          (==
            (id x)
            (int 0))
          (block
            (assign =
              (id x)
              (int 1))))))))

;;; 'ubyte x\nmain { if x == 0 { x = 1 } else { x = 2 } }'
(program
  (address $4000)
  (output raw)
  (target wendy2c)
  (imports)
  (vars
    (var ubyte x))
  (enums)
  (structs)
  (subs
    (subdef main main void
      (params)
      (block
        (if
          (==
            (id x)
            (int 0))
          (block
            (assign =
              (id x)
              (int 1)))
          (block
            (assign =
              (id x)
              (int 2))))))))

;;; 'ubyte x\nubyte y\nmain { if x { if y { x = 1 } else { x = 2 } } else { y = 3 } }'
(program
  (address $4000)
  (output raw)
  (target wendy2c)
  (imports)
  (vars
    (var ubyte x)
    (var ubyte y))
  (enums)
  (structs)
  (subs
    (subdef main main void
      (params)
      (block
        (if
          (id x)
          (block
            (if
              (id y)
              (block
                (assign =
                  (id x)
                  (int 1)))
              (block
                (assign =
                  (id x)
                  (int 2)))))
          (block
            (assign =
              (id y)
              (int 3))))))))

;;; 'ubyte i\nmain { while i < 10 { i = i + 1 } }'
(program
  (address $4000)
  (output raw)
  (target wendy2c)
  (imports)
  (vars
    (var ubyte i))
  (enums)
  (structs)
  (subs
    (subdef main main void
      (params)
      (block
        (while
          (<
            (id i)
            (int 10))
          (block
            (assign =
              (id i)
              (+
                (id i)
                (int 1)))))))))

;;; 'ubyte i\nmain { for i in 0 to 7 { txt.print("x") } }'
(program
  (address $4000)
  (output raw)
  (target wendy2c)
  (imports)
  (vars
    (var ubyte i))
  (enums)
  (structs)
  (subs
    (subdef main main void
      (params)
      (block
        (for i
          (int 0)
          (int 7)
          (block
            (exprstmt
              (call txt.print
                (str "x")))))))))

;;; 'main { repeat { break } }'
(program
  (address $4000)
  (output raw)
  (target wendy2c)
  (imports)
  (vars)
  (enums)
  (structs)
  (subs
    (subdef main main void
      (params)
      (block
        (repeat
          (block
            (break)))))))

;;; 'main { repeat 5 { txt.print(".") } }'
(program
  (address $4000)
  (output raw)
  (target wendy2c)
  (imports)
  (vars)
  (enums)
  (structs)
  (subs
    (subdef main main void
      (params)
      (block
        (repeat
          (int 5)
          (block
            (exprstmt
              (call txt.print
                (str ".")))))))))

;;; 'ubyte i\nmain { for i in 0 to 3 { if i == 2 { continue } txt.print("y") } }'
(program
  (address $4000)
  (output raw)
  (target wendy2c)
  (imports)
  (vars
    (var ubyte i))
  (enums)
  (structs)
  (subs
    (subdef main main void
      (params)
      (block
        (for i
          (int 0)
          (int 3)
          (block
            (if
              (==
                (id i)
                (int 2))
              (block
                (continue)))
            (exprstmt
              (call txt.print
                (str "y")))))))))

;;; 'sub f(ubyte c) { when c { $61 -> { txt.print("a") } $62, $63 -> { txt.print("bc") } else -> { txt.print("?") } } }'
(program
  (address $4000)
  (output raw)
  (target wendy2c)
  (imports)
  (vars)
  (enums)
  (structs)
  (subs
    (subdef f sub void
      (params
        (param ubyte c))
      (block
        (when
          (id c)
          (choice
            (vals
              (int 97))
            (block
              (exprstmt
                (call txt.print
                  (str "a")))))
          (choice
            (vals
              (int 98)
              (int 99))
            (block
              (exprstmt
                (call txt.print
                  (str "bc")))))
          (choice
            (vals)
            (block
              (exprstmt
                (call txt.print
                  (str "?"))))))))))

;;; 'ubyte x\nsub g() { defer txt.print("3") defer txt.print("2") txt.print("body") }'
(program
  (address $4000)
  (output raw)
  (target wendy2c)
  (imports)
  (vars
    (var ubyte x))
  (enums)
  (structs)
  (subs
    (subdef g sub void
      (params)
      (block
        (defer
          (exprstmt
            (call txt.print
              (str "3"))))
        (defer
          (exprstmt
            (call txt.print
              (str "2"))))
        (exprstmt
          (call txt.print
            (str "body")))))))

;;; 'ubyte x\nsub h() { defer if x { txt.print("z") } x = 1 }'
(program
  (address $4000)
  (output raw)
  (target wendy2c)
  (imports)
  (vars
    (var ubyte x))
  (enums)
  (structs)
  (subs
    (subdef h sub void
      (params)
      (block
        (defer
          (if
            (id x)
            (block
              (exprstmt
                (call txt.print
                  (str "z"))))))
        (assign =
          (id x)
          (int 1))))))

;;; 'sub r() -> ubyte { return 5 }'
(program
  (address $4000)
  (output raw)
  (target wendy2c)
  (imports)
  (vars)
  (enums)
  (structs)
  (subs
    (subdef r sub ubyte
      (params)
      (block
        (return
          (int 5))))))

;;; 'sub r2() -> bool { return true }'
(program
  (address $4000)
  (output raw)
  (target wendy2c)
  (imports)
  (vars)
  (enums)
  (structs)
  (subs
    (subdef r2 sub bool
      (params)
      (block
        (return
          (bool true))))))

;;; 'sub r3() { return }'
(program
  (address $4000)
  (output raw)
  (target wendy2c)
  (imports)
  (vars)
  (enums)
  (structs)
  (subs
    (subdef r3 sub void
      (params)
      (block
        (return)))))

;;; 'main { @($f001) = 7 }'
(program
  (address $4000)
  (output raw)
  (target wendy2c)
  (imports)
  (vars)
  (enums)
  (structs)
  (subs
    (subdef main main void
      (params)
      (block
        (assign =
          (mem
            (int 61441))
          (int 7))))))

;;; 'ubyte[4] arr\nmain { arr[0] = 1 arr[1] = arr[0] + 2 }'
(program
  (address $4000)
  (output raw)
  (target wendy2c)
  (imports)
  (vars
    (var ubyte[4] arr))
  (enums)
  (structs)
  (subs
    (subdef main main void
      (params)
      (block
        (assign =
          (idx
            (id arr)
            (int 0))
          (int 1))
        (assign =
          (idx
            (id arr)
            (int 1))
          (+
            (idx
              (id arr)
              (int 0))
            (int 2)))))))

;;; 'main { %asm {{\nnop\n}} }'
(program
  (address $4000)
  (output raw)
  (target wendy2c)
  (imports)
  (vars)
  (enums)
  (structs)
  (subs
    (subdef main main void
      (params)
      (block
        (asm "nop")))))

;;; 'ubyte a\nubyte b\nmain { while a < 8 { for b in 0 to a { if b == 3 { break } } a = a + 1 } }'
(program
  (address $4000)
  (output raw)
  (target wendy2c)
  (imports)
  (vars
    (var ubyte a)
    (var ubyte b))
  (enums)
  (structs)
  (subs
    (subdef main main void
      (params)
      (block
        (while
          (<
            (id a)
            (int 8))
          (block
            (for b
              (int 0)
              (id a)
              (block
                (if
                  (==
                    (id b)
                    (int 3))
                  (block
                    (break)))))
            (assign =
              (id a)
              (+
                (id a)
                (int 1)))))))))


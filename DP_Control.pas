{
  Модуль управления:
  + сделать паузу считывания для каждой кнопки
  + пауза для кнопки мыши
  + заменить конкретные переменные к клавишами на массив
  * значения: https://winkhaus-shop.ru/wp-content/uploads/2021/11/kak-uznat-kody-klavish-na-klaviature.jpg
}
unit DP_Control;

Uses GraphABC;

type
  TKey = record
    code: integer;
    state: boolean;
  end;

var
  BackColor, SelColor, MainColor: Color;
  Keys: array of Tkey;
  ///Координаты мыши
  MouseX, MouseY: integer;
  ///Нажата ли кнопка мыши?
  MousePressed: boolean;
  ///Двигается ли мышь?
  MouseMoved: boolean;
  ///Код нажатой кнопки мыши
  MouseCode: integer;
  ///Изменился ли размер окна?
  Resized: boolean;
  Pause: integer;
  ActiveEdit := -1;
  ///Счётчик мыши для отслеживания первого нажатия
  MouseCount := 0;
  
function KeyPressed(): boolean;
begin
  if Keys.Length = 0 then
    Result := false
  else
    Result := true;
end;

/// Не позволяет создать массив длиной меньше нуля
function NotZero(Key: integer): integer;
begin
  if Key < 0 then
    Result := 0
  else
    Result := Key;
end;

function FindKey(Key: integer): integer;
var
  index: Integer;
  found := False;
begin
  
  // Перебираем массив для поиска значения
  var tmpKeys := Keys;
  for index := 0 to Length(tmpKeys) - 1 do
  begin
    if tmpKeys[index].code = Key then
    begin
      found := True;
      Break; // Выход из цикла, если элемент найден
    end;
  end;
  
  // Проверяем, найден ли элемент и выводим результат
  if found then
    Result := index
  else
    Result := -1;
end;

function IsKeyPressed(Key: integer): boolean;
begin
  Result := False;
  if (FindKey(Key) > -1) and
     Keys[FindKey(Key)].state then
  begin
    Result := True;
    Keys[FindKey(Key)].state := False;
  end;
end;

procedure PushKey(Key: integer);
begin
  if not FindKey(Key) > -1 then
  begin
    var Temp := Keys;
    SetLength(Temp, NotZero(Keys.Length + 1));
    for i: integer := 0 to Keys.Length - 1 do
      Temp[i] := Keys[i];
    Temp[Keys.Length].code := Key;
    Temp[Keys.Length].state := True;
    Keys := Temp;
  end;
end;

procedure DelKey(Key: integer);
begin
  var Temp := Keys;
  SetLength(Temp, NotZero(Keys.Length - 1));
  var pos := 0;
  for i: integer := 0 to Keys.Length - 1 do
  begin
    if Keys[i].code = Key then
      continue
    else
    begin
      Temp[pos] := Keys[i];
      pos += 1;
    end;
  end;
  SetLength(Temp, pos);
  Keys := Temp;
end;

function AnyKeyPressed: boolean;
begin
  if Keys.Length > 0 then
    Result := True
  else
    Result := False;
end;

procedure KeyDown(Key: integer);
begin
  PushKey(Key);
end;

procedure KeyUp(Key: integer);
begin
  DelKey(Key);
end;

procedure MouseDown(x, y, mb: integer);
begin
  MouseX := x;
  MouseY := y;
  MousePressed := True;
  MouseCode := mb;
  Pause := 128;
  ActiveEdit := -1;
end;

procedure MouseMove(x, y, mb: integer);
begin
  MouseX := x;
  MouseY := y;
  MouseCode := mb;
  MouseMoved := True;
  Pause := 128;
end;

procedure MouseUp(x, y, mb: integer);
begin
  MousePressed := False;
end;

function MousePressedFirstTime(): boolean;
begin
  Result := False;
  if MousePressed and (MouseCount = 0) then
  begin
    Result := True;
    MouseCount += 1;
  end;
  if not MousePressed then
    MouseCount := 0;
end;
///Функция кнопка. Есть подсветка при наведении курсора. При нажатии возвращает True
function Button(X, Y, _W, _H: integer; Title: string): boolean;
begin
  Brush.Color := BackColor;
  FillRect(X, Y, X + _W, Y + _H);
  if (MouseX > X) and (MouseX < X + _W) and
     (MouseY > Y) and (MouseY < Y + _H) then
  begin
    Brush.Color := SelColor;
    if MousePressed then Result := True;
    while MousePressed do;
  end else
    Brush.Color := MainColor;
  FillRect(X + 1, Y + 1, X + _W - 1, Y + _H - 1);
  DrawTextCentered(X, Y, X + _W, Y + _H, Title);
end;

procedure Resize := Resized := True;

begin
  SetLength(Keys, 0);
  OnKeyDown := KeyDown;
  OnKeyUp := KeyUp;
  OnMouseDown := MouseDown;
  OnMouseMove := MouseMove;
  OnMouseUp := MouseUp;
  OnResize := Resize;
end.

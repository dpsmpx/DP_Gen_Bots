{
  Модуль управления: клавиатура и мышь для GraphABC.

  Состояние клавиш хранится в массиве, индексированном кодом клавиши.
  Это важно для корректности, а не только для скорости: обработчики
  OnKeyDown/OnKeyUp вызываются в потоке окна, а читает состояние главный
  поток программы. Запись одного элемента массива атомарна, поэтому
  пересобирать массив (и ловить на этом гонки и выход за границы) не нужно.

  Коды клавиш: https://learn.microsoft.com/windows/win32/inputdev/virtual-key-codes
}
unit DP_Control;

uses GraphABC;

const
  ///Размер таблицы состояний клавиш: коды виртуальных клавиш Windows лежат в 0..255
  KEY_CODE_LIMIT = 256;
  ///Маска, отсекающая флаги модификаторов (Shift/Ctrl/Alt) от кода клавиши
  KEY_CODE_MASK = $FFFF;

var
  ///Удерживается ли клавиша прямо сейчас
  keyHeld: array[0..KEY_CODE_LIMIT - 1] of boolean;
  ///Было нажатие, которое ещё не забрал IsKeyPressed
  keyHitPending: array[0..KEY_CODE_LIMIT - 1] of boolean;
  ///Координаты мыши
  MouseX, MouseY: integer;
  ///Нажата ли кнопка мыши?
  MousePressed: boolean;
  ///Код нажатой кнопки мыши
  MouseCode: integer;
  ///Изменился ли размер окна?
  Resized: boolean;

/// Приводит код клавиши к индексу таблицы; -1, если код не представим
function NormalizeKeyCode(Key: integer): integer;
begin
  var code := Key and KEY_CODE_MASK;
  if (code >= 0) and (code < KEY_CODE_LIMIT) then
    Result := code
  else
    Result := -1;
end;

/// Удерживается ли хотя бы одна клавиша
function AnyKeyPressed: boolean;
begin
  Result := False;
  for var code := 0 to KEY_CODE_LIMIT - 1 do
    if keyHeld[code] then
    begin
      Result := True;
      exit;
    end;
end;

/// Удерживается ли конкретная клавиша
function IsKeyHeld(Key: integer): boolean;
begin
  var code := NormalizeKeyCode(Key);
  Result := (code >= 0) and keyHeld[code];
end;

/// Разовое срабатывание: возвращает True один раз на каждое нажатие клавиши
function IsKeyPressed(Key: integer): boolean;
begin
  var code := NormalizeKeyCode(Key);
  Result := (code >= 0) and keyHitPending[code];
  if Result then
    keyHitPending[code] := False;
end;

procedure KeyDown(Key: integer);
begin
  var code := NormalizeKeyCode(Key);
  if code < 0 then exit;
  // Автоповтор клавиши шлёт KeyDown многократно — новым нажатием считаем
  // только переход из отпущенного состояния в удерживаемое
  if not keyHeld[code] then
    keyHitPending[code] := True;
  keyHeld[code] := True;
end;

procedure KeyUp(Key: integer);
begin
  var code := NormalizeKeyCode(Key);
  if code >= 0 then
    keyHeld[code] := False;
end;

procedure MouseDown(x, y, mb: integer);
begin
  MouseX := x;
  MouseY := y;
  MousePressed := True;
  MouseCode := mb;
end;

procedure MouseMove(x, y, mb: integer);
begin
  MouseX := x;
  MouseY := y;
  MouseCode := mb;
end;

procedure MouseUp(x, y, mb: integer);
begin
  MouseX := x;
  MouseY := y;
  MousePressed := False;
end;

procedure Resize := Resized := True;

begin
  for var code := 0 to KEY_CODE_LIMIT - 1 do
  begin
    keyHeld[code] := False;
    keyHitPending[code] := False;
  end;
  OnKeyDown := KeyDown;
  OnKeyUp := KeyUp;
  OnMouseDown := MouseDown;
  OnMouseMove := MouseMove;
  OnMouseUp := MouseUp;
  OnResize := Resize;
end.

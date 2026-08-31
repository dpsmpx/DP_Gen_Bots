{
  Мир симуляции: клетки, генерация карты, содержимое поля.

  У каждого бота своя копия поля: боты не взаимодействуют между собой,
  каждый проходит собственный прогон в одинаковой стартовой раскладке.

  Модуль не зависит от GraphABC — модель можно прогонять без окна.
}
unit DP_World;

uses DP_Config;

type
  CellType = (Empty, Wall, Apple, Poison, BotCell);

  ///Координата клетки. Собственный тип вместо Point из GraphABC,
  ///чтобы модель не тянула за собой графическую библиотеку.
  CellPoint = record
    x, y: integer;
  end;

  ///Стартовая раскладка, одинаковая для всех ботов поколения
  LayoutInfo = record
    startX, startY: integer;
    appleCount: integer;
  end;

var
  ///Поле каждого бота
  botFields: array[0..MAXIMUM_BOTS - 1] of array[0..FIELD_WIDTH - 1, 0..FIELD_HEIGHT - 1] of CellType;
  ///Сколько яблок сейчас на поле каждого бота. Счётчик избавляет от обхода
  ///всех 900 клеток каждый такт ради подсчёта.
  botAppleCount: array[0..MAXIMUM_BOTS - 1] of integer;

function MakeCellPoint(x, y: integer): CellPoint;
begin
  Result.x := x;
  Result.y := y;
end;

/// Лежит ли клетка внутри поля
function IsInsideField(x, y: integer): boolean
  := (x >= 0) and (x < FIELD_WIDTH) and (y >= 0) and (y < FIELD_HEIGHT);

/// Клетка перед ботом с учётом направления (0 — вверх, далее по часовой)
function GetFrontPosition(x, y, direction: integer): CellPoint;
begin
  case direction of
    0: Result := MakeCellPoint(x, (y - 1 + FIELD_HEIGHT) mod FIELD_HEIGHT);
    1: Result := MakeCellPoint((x + 1) mod FIELD_WIDTH, y);
    2: Result := MakeCellPoint(x, (y + 1) mod FIELD_HEIGHT);
    3: Result := MakeCellPoint((x - 1 + FIELD_WIDTH) mod FIELD_WIDTH, y);
  else
    // Направление всегда приводится по модулю 4, но без этой ветки любое
    // нарушение инварианта молча вернуло бы неинициализированный результат.
    raise new System.ArgumentOutOfRangeException('direction', 'Направление должно быть 0..3');
  end;
end;

/// Случайная свободная клетка на поле бота, или (-1, -1), если её нет
function FindEmptyPosition(botIndex: integer): CellPoint;
var
  attempts: integer;
begin
  attempts := 0;
  repeat
    Result := MakeCellPoint(Random(FIELD_WIDTH), Random(FIELD_HEIGHT));
    Inc(attempts);
    if attempts > 1000 then
    begin
      Result := MakeCellPoint(-1, -1);
      exit;
    end;
  until botFields[botIndex, Result.x, Result.y] = Empty;
end;

/// Случайная клетка заданного типа, или (-1, -1). Равномерный выбор за один
/// проход (резервуарная выборка), поэтому список координат не нужен.
function FindCellOfType(botIndex: integer; wanted: CellType): CellPoint;
var
  seen: integer;
begin
  Result := MakeCellPoint(-1, -1);
  seen := 0;
  for var x := 0 to FIELD_WIDTH - 1 do
    for var y := 0 to FIELD_HEIGHT - 1 do
      if botFields[botIndex, x, y] = wanted then
      begin
        Inc(seen);
        if Random(seen) = 0 then
          Result := MakeCellPoint(x, y);
      end;
end;

/// Кладёт яблоко в случайную свободную клетку. False, если места нет.
function PlaceApple(botIndex: integer): boolean;
begin
  var position := FindEmptyPosition(botIndex);
  Result := position.x >= 0;
  if Result then
  begin
    botFields[botIndex, position.x, position.y] := Apple;
    botAppleCount[botIndex] += 1;
  end;
end;

/// Готовит новую карту и раскладывает содержимое, одинаковое для всех ботов.
///
/// Стены разбрасываются случайно, как и раньше, — характер карты сохраняется.
/// Связность обеспечивается не проверкой на каждую стену, а один раз в конце:
/// свободные клетки размечаются на компоненты, крупнейшая дорастает до нужного
/// размера по своей границе, всё остальное становится стеной. Прежняя версия
/// после каждой стены запускала обход в ширину, чтобы убедиться, что она не
/// отрезала часть поля, — это стоило сотен обходов на поколение и было самым
/// дорогим местом всей программы.
function GenerateField(wallCount, appleCount, poisonCount: integer): LayoutInfo;
const
  INTERIOR_CELLS = (FIELD_WIDTH - 2) * (FIELD_HEIGHT - 2);
var
  field: array[0..FIELD_WIDTH - 1, 0..FIELD_HEIGHT - 1] of CellType;
  ///Принадлежит ли клетка крупнейшей связной области
  inMain: array[0..FIELD_WIDTH - 1, 0..FIELD_HEIGHT - 1] of boolean;
  ///Помечена ли клетка при разметке компонент
  labelled: array[0..FIELD_WIDTH - 1, 0..FIELD_HEIGHT - 1] of boolean;
  ///Стоит ли клетка в очереди кандидатов на присоединение
  queued: array[0..FIELD_WIDTH - 1, 0..FIELD_HEIGHT - 1] of boolean;
  interior, queue, frontier, freeCells: array[0..INTERIOR_CELLS - 1] of CellPoint;
  frontierCount, freeCount: integer;
  offsets: array[0..3] of CellPoint;

  function IsInterior(x, y: integer): boolean
    := (x >= 1) and (x <= FIELD_WIDTH - 2) and (y >= 1) and (y <= FIELD_HEIGHT - 2);

  /// Ставит стену в очередь кандидатов на присоединение к области
  procedure EnqueueFrontier(x, y: integer);
  begin
    if not IsInterior(x, y) then exit;
    if queued[x, y] or (field[x, y] <> Wall) then exit;
    queued[x, y] := true;
    frontier[frontierCount] := MakeCellPoint(x, y);
    Inc(frontierCount);
  end;

  /// Забирает случайную свободную клетку из списка
  function TakeFreeCell: CellPoint;
  begin
    if freeCount = 0 then
    begin
      Result := MakeCellPoint(-1, -1);
      exit;
    end;
    var index := Random(freeCount);
    Result := freeCells[index];
    freeCells[index] := freeCells[freeCount - 1];
    Dec(freeCount);
  end;

begin
  offsets[0] := MakeCellPoint(0, -1);
  offsets[1] := MakeCellPoint(0, 1);
  offsets[2] := MakeCellPoint(-1, 0);
  offsets[3] := MakeCellPoint(1, 0);

  for var x := 0 to FIELD_WIDTH - 1 do
    for var y := 0 to FIELD_HEIGHT - 1 do
    begin
      field[x, y] := Wall;
      inMain[x, y] := false;
      labelled[x, y] := false;
      queued[x, y] := false;
    end;

  var interiorCount := 0;
  for var x := 1 to FIELD_WIDTH - 2 do
    for var y := 1 to FIELD_HEIGHT - 2 do
    begin
      field[x, y] := Empty;
      interior[interiorCount] := MakeCellPoint(x, y);
      Inc(interiorCount);
    end;

  var freeTarget := INTERIOR_CELLS - wallCount;
  if freeTarget < 1 then freeTarget := 1;
  if freeTarget > INTERIOR_CELLS then freeTarget := INTERIOR_CELLS;

  // Случайные стены: перемешиваем список внутренних клеток и берём первые
  for var index := interiorCount - 1 downto 1 do
  begin
    var other := Random(index + 1);
    var swap := interior[index];
    interior[index] := interior[other];
    interior[other] := swap;
  end;
  for var index := 0 to interiorCount - freeTarget - 1 do
    field[interior[index].x, interior[index].y] := Wall;

  // Разметка компонент свободного пространства; ищем крупнейшую
  var bestSize := 0;
  var bestStart := MakeCellPoint(-1, -1);
  for var index := 0 to interiorCount - 1 do
  begin
    var origin := interior[index];
    if labelled[origin.x, origin.y] or (field[origin.x, origin.y] = Wall) then continue;
    var head := 0;
    var tail := 0;
    queue[tail] := origin;
    Inc(tail);
    labelled[origin.x, origin.y] := true;
    while head < tail do
    begin
      var cell := queue[head];
      Inc(head);
      for var i := 0 to 3 do
      begin
        var nx := cell.x + offsets[i].x;
        var ny := cell.y + offsets[i].y;
        if IsInterior(nx, ny) and (field[nx, ny] <> Wall) and not labelled[nx, ny] then
        begin
          labelled[nx, ny] := true;
          queue[tail] := MakeCellPoint(nx, ny);
          Inc(tail);
        end;
      end;
    end;
    if tail > bestSize then
    begin
      bestSize := tail;
      bestStart := origin;
    end;
  end;

  // Отмечаем крупнейшую связную область
  var mainSize := 0;
  if bestStart.x >= 0 then
  begin
    var head := 0;
    var tail := 0;
    queue[tail] := bestStart;
    Inc(tail);
    inMain[bestStart.x, bestStart.y] := true;
    while head < tail do
    begin
      var cell := queue[head];
      Inc(head);
      for var i := 0 to 3 do
      begin
        var nx := cell.x + offsets[i].x;
        var ny := cell.y + offsets[i].y;
        if IsInterior(nx, ny) and (field[nx, ny] <> Wall) and not inMain[nx, ny] then
        begin
          inMain[nx, ny] := true;
          queue[tail] := MakeCellPoint(nx, ny);
          Inc(tail);
        end;
      end;
    end;
    mainSize := tail;
  end;

  // Отрезанные куски заваливаются ДО прорастания. Если этого не сделать,
  // растущая область может сомкнуться с таким куском, но его клетки так и
  // останутся неучтёнными — и стен в итоге окажется больше заказанного.
  for var x := 1 to FIELD_WIDTH - 2 do
    for var y := 1 to FIELD_HEIGHT - 2 do
      if not inMain[x, y] then
        field[x, y] := Wall;

  // Граница области: стены, у которых есть сосед внутри области
  frontierCount := 0;
  for var x := 1 to FIELD_WIDTH - 2 do
    for var y := 1 to FIELD_HEIGHT - 2 do
      if field[x, y] = Wall then
        for var i := 0 to 3 do
        begin
          var nx := x + offsets[i].x;
          var ny := y + offsets[i].y;
          if IsInterior(nx, ny) and inMain[nx, ny] then
          begin
            EnqueueFrontier(x, y);
            break;
          end;
        end;

  // Дорастим область по границе ровно до нужного числа свободных клеток
  while (mainSize < freeTarget) and (frontierCount > 0) do
  begin
    var index := Random(frontierCount);
    var cell := frontier[index];
    frontier[index] := frontier[frontierCount - 1];
    Dec(frontierCount);
    queued[cell.x, cell.y] := false;

    field[cell.x, cell.y] := Empty;
    inMain[cell.x, cell.y] := true;
    Inc(mainSize);
    for var i := 0 to 3 do
      EnqueueFrontier(cell.x + offsets[i].x, cell.y + offsets[i].y);
  end;

  // Собираем свободные клетки для раскладки содержимого
  freeCount := 0;
  for var x := 1 to FIELD_WIDTH - 2 do
    for var y := 1 to FIELD_HEIGHT - 2 do
      if inMain[x, y] then
      begin
        freeCells[freeCount] := MakeCellPoint(x, y);
        Inc(freeCount);
      end;

  // Старт, яблоки и яд разыгрываются один раз на поколение. Пока раскладка
  // делалась отдельно для каждого бота, 128 ботов проходили 128 разных
  // испытаний, а их приспособленности сравнивались напрямую в отборе.
  var startCell := TakeFreeCell;
  Result.startX := startCell.x;
  Result.startY := startCell.y;
  if startCell.x >= 0 then
    field[startCell.x, startCell.y] := BotCell;

  Result.appleCount := 0;
  for var i := 1 to appleCount do
  begin
    var cell := TakeFreeCell;
    if cell.x < 0 then break;
    field[cell.x, cell.y] := Apple;
    Inc(Result.appleCount);
  end;
  for var i := 1 to poisonCount do
  begin
    var cell := TakeFreeCell;
    if cell.x < 0 then break;
    field[cell.x, cell.y] := Poison;
  end;

  for var botIndex := 0 to MAXIMUM_BOTS - 1 do
  begin
    for var x := 0 to FIELD_WIDTH - 1 do
      for var y := 0 to FIELD_HEIGHT - 1 do
        botFields[botIndex, x, y] := field[x, y];
    botAppleCount[botIndex] := Result.appleCount;
  end;
end;

/// Поддержание содержимого поля: минимум яблок и распад яблок в яд.
procedure UpdateWorld;
begin
  for var botIndex := 0 to MAXIMUM_BOTS - 1 do
  begin
    if botAppleCount[botIndex] < MINIMUM_APPLES then
      PlaceApple(botIndex);

    // Розыгрыш идёт по числу яблок (порядка тридцати), а не по всем 900
    // клеткам поля; сканировать поле приходится только когда распад
    // действительно случился — примерно в трёх процентах тактов.
    var decayCount := 0;
    for var apple := 1 to botAppleCount[botIndex] do
      if Random < APPLE_DECAY_PROBABILITY then
        Inc(decayCount);

    while decayCount > 0 do
    begin
      var position := FindCellOfType(botIndex, Apple);
      if position.x < 0 then break;
      botFields[botIndex, position.x, position.y] := Poison;
      botAppleCount[botIndex] -= 1;
      Dec(decayCount);
    end;
  end;
end;

begin
end.

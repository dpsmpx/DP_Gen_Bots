{
  Отрисовка: поле выбранного бота и график по поколениям.

  Показывается ровно один бот. Прежняя версия складывала поля всех 128
  ботов в одну картинку: для каждой из 900 клеток она обходила всю
  популяцию, выясняя, есть ли там у кого-нибудь яблоко, и объединяла
  посещённые клетки. Это стоило 115 200 итераций на кадр и показывало
  наложение 128 независимых миров, то есть картину, которой не существует.
}
unit DP_Render;

uses GraphABC, DP_Config, DP_World, DP_Bot, DP_Evolution, DP_Interface;

var
  ///Чьё поле показывать
  selectedBot: integer := 0;
  emptyCellColor: Color := clGray;
  wallColor: Color := clBlack;
  appleColor: Color := clGreen;
  poisonColor: Color := clRed;
  visitedColor: Color := ARGB(90, 255, 255, 0);
  botColor: Color := clLime;

procedure SelectBot(delta: integer);
begin
  selectedBot := (selectedBot + delta + MAXIMUM_BOTS) mod MAXIMUM_BOTS;
end;

/// Выбирает самого приспособленного бота текущего поколения
procedure SelectBestBot;
begin
  var best := 0;
  for var botIndex := 1 to MAXIMUM_BOTS - 1 do
    if bots[botIndex].fitness > bots[best].fitness then
      best := botIndex;
  selectedBot := best;
end;

procedure SetupWindow;
begin
  SetWindowTitle('Генетические боты');
  SetWindowSize(WINDOW_WIDTH, WINDOW_HEIGHT);
  CenterWindow;
  LockDrawing;
end;

procedure UpdateStatus;
begin
  SetWindowTitle('GenBots | поколение ' + generationNumber.ToString +
                 ' | живых ' + activeBotCount.ToString +
                 ' | средняя ' + currentAverageFitness.ToString('F1') +
                 ' | мутация ' + currentMutationRate.ToString('F3'));
end;

procedure ShowStartupMessage;
begin
  ClearWindow(emptyCellColor);
  DrawRectangledText(WINDOW_WIDTH div 2 - 170, WINDOW_HEIGHT div 2 - 30, 340, 60,
    'Генетические боты' + newline +
    'пробел — пауза, G — график, F — поле, стрелки — выбор бота');
  Redraw;
end;

procedure RenderFieldView;
begin
  ClearWindow(emptyCellColor);

  // Посещённые клетки рисуются под содержимым, иначе полупрозрачная заливка
  // затирает яблоки и яд
  Brush.Color := visitedColor;
  for var x := 0 to FIELD_WIDTH - 1 do
    for var y := 0 to FIELD_HEIGHT - 1 do
      if bots[selectedBot].visited[x, y] then
        FillRect(x * PIXEL_SIZE, y * PIXEL_SIZE, (x + 1) * PIXEL_SIZE, (y + 1) * PIXEL_SIZE);

  for var x := 0 to FIELD_WIDTH - 1 do
    for var y := 0 to FIELD_HEIGHT - 1 do
      case botFields[selectedBot, x, y] of
        Wall:
          begin
            Brush.Color := wallColor;
            FillRect(x * PIXEL_SIZE, y * PIXEL_SIZE, (x + 1) * PIXEL_SIZE, (y + 1) * PIXEL_SIZE);
          end;
        Apple:
          begin
            Brush.Color := appleColor;
            FillCircle(x * PIXEL_SIZE + PIXEL_SIZE div 2, y * PIXEL_SIZE + PIXEL_SIZE div 2, PIXEL_SIZE div 4);
          end;
        Poison:
          begin
            Brush.Color := poisonColor;
            FillCircle(x * PIXEL_SIZE + PIXEL_SIZE div 2, y * PIXEL_SIZE + PIXEL_SIZE div 2, PIXEL_SIZE div 4);
          end;
      end;

  if bots[selectedBot].active then
  begin
    Pen.Color := clCyan;
    Brush.Color := botColor;
    var x := bots[selectedBot].x;
    var y := bots[selectedBot].y;
    Rectangle(x * PIXEL_SIZE, y * PIXEL_SIZE, (x + 1) * PIXEL_SIZE, (y + 1) * PIXEL_SIZE);
  end;

  var state := 'жив';
  if not bots[selectedBot].active then state := 'погиб';
  DrawRectangledText(4, WINDOW_HEIGHT - 56, WINDOW_WIDTH - 8, 52,
    'бот ' + selectedBot.ToString + ' из ' + MAXIMUM_BOTS.ToString + ', ' + state + newline +
    'приспособленность ' + bots[selectedBot].fitness.ToString +
    ', действий ' + bots[selectedBot].actionCount.ToString + ' из ' + MAXIMUM_ACTIONS.ToString + newline +
    'команда генома ' + CurrentCommand(selectedBot).ToString +
    ' в позиции ' + bots[selectedBot].genomePosition.ToString);
  Redraw;
end;

/// Рисует одну серию в своём собственном масштабе. Общий масштаб для
/// приспособленности (очки) и длительности поколения (миллисекунды) делал
/// вторую кривую нечитаемой: она прижималась к нижнему краю.
procedure RenderSeries(data: array of real; count, xLeft, yTop, width, height: integer;
                       lineColor: Color; drawPoints: boolean);
var
  minValue, maxValue, scaleX, scaleY: real;

  function PointX(index: integer): integer;
  begin
    // Индекс 0 — самое свежее поколение, поэтому время идёт слева направо
    if count > 1 then
      Result := Round(xLeft + width - index * scaleX)
    else
      Result := xLeft + width;
  end;

  function PointY(index: integer): integer;
  begin
    if scaleY = 0 then
      Result := Round(yTop + height / 2)
    else
      Result := Round(yTop + height - (data[index] - minValue) * scaleY);
  end;

begin
  if count < 1 then exit;
  minValue := data[0];
  maxValue := data[0];
  for var index := 1 to count - 1 do
  begin
    if data[index] < minValue then minValue := data[index];
    if data[index] > maxValue then maxValue := data[index];
  end;
  if count > 1 then
    scaleX := width / (count - 1)
  else
    scaleX := 0;
  if maxValue = minValue then
    scaleY := 0
  else
    scaleY := height / (maxValue - minValue);

  Pen.Color := lineColor;
  Pen.Width := 1;
  MoveTo(PointX(0), PointY(0));
  for var index := 1 to count - 1 do
    LineTo(PointX(index), PointY(index));

  if drawPoints then
  begin
    Brush.Color := lineColor;
    Pen.Color := lineColor;
    for var index := 0 to count - 1 do
      FillCircle(PointX(index), PointY(index), 2);
  end;
end;

procedure RenderGraphView(xLeft, yTop, width, height: integer);
begin
  ClearWindow(emptyCellColor);
  if historyFilled = 0 then
  begin
    ShowStartupMessage;
    exit;
  end;

  Pen.Color := clLightGray;
  Pen.Width := 1;
  for var index := 1 to 4 do
  begin
    Line(xLeft, Round(yTop + index * height / 5), xLeft + width, Round(yTop + index * height / 5));
    Line(Round(xLeft + index * width / 5), yTop, Round(xLeft + index * width / 5), yTop + height);
  end;

  // Считается только заполненная часть истории: незаполненные нули
  // раньше занижали минимум и среднее все первые сто поколений.
  RenderSeries(generationDurations, historyFilled, xLeft, yTop, width, height, clCyan, false);
  RenderSeries(averageFitnessHistory, historyFilled, xLeft, yTop, width, height, clYellow, true);

  var minFitness := averageFitnessHistory[0];
  var maxFitness := averageFitnessHistory[0];
  var meanFitness := 0.0;
  for var index := 0 to historyFilled - 1 do
  begin
    if averageFitnessHistory[index] < minFitness then minFitness := averageFitnessHistory[index];
    if averageFitnessHistory[index] > maxFitness then maxFitness := averageFitnessHistory[index];
    meanFitness += averageFitnessHistory[index];
  end;
  meanFitness /= historyFilled;

  DrawRectangledText(4, WINDOW_HEIGHT - 92, WINDOW_WIDTH - 8, 88,
    'поколение ' + generationNumber.ToString +
    '   яблок ' + currentAppleCount.ToString +
    '   стен ' + currentWallCount.ToString +
    '   мутация ' + currentMutationRate.ToString('F3') + newline +
    'приспособленность (жёлтая): макс ' + maxFitness.ToString('F1') +
    ', мин ' + minFitness.ToString('F1') +
    ', средняя ' + meanFitness.ToString('F1') + newline +
    'длительность поколения (голубая), своя шкала' + newline +
    'пробел — пауза, F — поле, стрелки — выбор бота');
  Redraw;
end;

begin
end.

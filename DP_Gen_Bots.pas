uses GraphABC, DP_Control, DP_Interface;

const
  MAXIMUM_BOTS          = 128;
  MINIMUM_BOTS          = 32;
  ///Длина генома. Гены хранят значения 0..GENOME_LENGTH-1 и служат
  ///одновременно кодом команды (по остатку от COMMAND_COUNT) и смещением
  ///перехода. Поэтому мутация одного гена осмысленно меняет обе роли.
  GENOME_LENGTH         = 64;
  ///Сколько различных команд понимает бот
  COMMAND_COUNT         = 6;
  ///Сколько ситуаций различает сенсор команды 4; столько же генов подряд
  ///после неё образуют таблицу переходов
  SENSOR_SITUATIONS     = 6;
  FIELD_WIDTH           = 30;
  FIELD_HEIGHT          = 30;
  PIXEL_SIZE            = 15;
  WINDOW_WIDTH          = FIELD_WIDTH * PIXEL_SIZE;
  WINDOW_HEIGHT         = FIELD_HEIGHT * PIXEL_SIZE;
  APPLE_DECAY_PROBABILITY = 0.001;
  ELITE_BOT_COUNT       = 12;
  BASE_MUTATION_RATE    = 0.03;
  MAXIMUM_MUTATION_RATE = 0.10;
  STAGNATION_THRESHOLD  = 3;
  MUTATION_INCREMENT    = 0.01;
  MUTATION_DECREMENT    = 0.005;
  MAXIMUM_ACTIONS       = 500;
  ///Порог средней приспособленности, выше которого среда усложняется
  FITNESS_THRESHOLD     = 40;
  ///Как часто пересматриваются мутация и сложность среды, в поколениях
  ENVIRONMENT_ADAPT_INTERVAL = 25;
  MINIMUM_APPLES        = 5;
  MAXIMUM_WALLS         = 360;
  INITIAL_APPLES        = 30;
  INITIAL_WALLS         = 270;
  POISON_COUNT          = 10;
  ///Награда за съеденное яблоко
  FITNESS_APPLE         = 6;
  ///Награда за уничтожение яда перед собой
  FITNESS_KILL_POISON   = 3;
  ///Награда за первое посещение клетки
  FITNESS_NEW_CELL      = 1;
  ///Зерно генератора случайных чисел. Фиксировано, чтобы прогоны были
  ///воспроизводимы; поставьте 0, чтобы каждый запуск отличался.
  RANDOM_SEED           = 20240816;

type
  CellType = (Empty, Wall, Apple, Poison, BotCell);
  ViewModeType = (ViewField, ViewGraph);
  Bot = record
    active: boolean;
    x, y: integer;
    direction: integer;
    genomePosition: integer;
    genome: array[0..GENOME_LENGTH - 1] of byte;
    actionCount: integer;
    fitness: integer;
    visited: array[0..FIELD_WIDTH - 1, 0..FIELD_HEIGHT - 1] of boolean;
  end;
  DisjointSetUnion = record
    parent: array[0..FIELD_WIDTH * FIELD_HEIGHT - 1] of integer;
    rank: array[0..FIELD_WIDTH * FIELD_HEIGHT - 1] of integer;
  end;

var
  botFields: array[0..MAXIMUM_BOTS - 1] of array[0..FIELD_WIDTH - 1, 0..FIELD_HEIGHT - 1] of CellType;
  renderField: array[0..FIELD_WIDTH - 1, 0..FIELD_HEIGHT - 1] of CellType;
  bots: array[0..MAXIMUM_BOTS - 1] of Bot;
  maximumThinkTime: integer := 8;
  activeBotCount: integer := MAXIMUM_BOTS;
  generationNumber: integer := 0;
  generationStartTime: integer;
  generationDurations: array of real;
  averageFitnessHistory: array of real;
  historySegmentCount: integer := 100;
  ///Сколько элементов истории реально заполнено. Без этого первые сто
  ///поколений рисуются вместе с нулями-заполнителями, которые сбивают
  ///и масштаб графика, и подписи под ним.
  historyFilled: integer := 0;
  ///Максимальная приспособленность в последнем поколении
  currentMaximumFitness: integer := 0;
  ///Файл журнала прогона
  logFile: Text;
  isLogOpen: boolean := False;
  ///Что показывать в окне: поле симуляции или график по поколениям
  viewMode: ViewModeType := ViewGraph;
  isSimulationPaused: boolean := False;
  ///Состояние кнопки мыши на прошлом кадре — для детекции фронта нажатия
  wasMousePressed: boolean := False;
  skipRenderGenerations: integer := 0;
  emptyCellColor: Color := clGray;
  wallColor: Color := clBlack;
  appleColor: Color := clGreen;
  poisonColor: Color := clRed;
  ///Средняя приспособленность за предыдущее окно наблюдения
  previousWindowAverage: real := 0;
  ///Накопитель приспособленности внутри текущего окна
  windowFitnessSum: real := 0;
  windowGenerations: integer := 0;
  stagnationCounter: integer := 0;
  currentMutationRate: real := BASE_MUTATION_RATE;
  currentAppleCount: integer := INITIAL_APPLES;
  ///Сколько яблок сейчас на поле каждого бота. Позволяет не обходить
  ///все 900 клеток каждый такт ради подсчёта.
  botAppleCount: array[0..MAXIMUM_BOTS - 1] of integer;
  currentWallCount: integer := INITIAL_WALLS;

procedure ResetField; forward;

function Minimum(a, b: real): real;
begin
  if a < b then Result := a else Result := b;
end;

function Maximum(a, b: real): real;
begin
  if a > b then Result := a else Result := b;
end;

function Minimum(a, b: integer): integer;
begin
  if a < b then Result := a else Result := b;
end;

function Maximum(a, b: integer): integer;
begin
  if a > b then Result := a else Result := b;
end;

procedure DrawRectangledText(startX, startY, width, height: integer; text: string);
begin
  Pen.Color := clCyan;
  Brush.Color := ARGB(128, 0, 0, 0);
  Rectangle(startX, startY, startX + width, startY + height);
  Font.Color := clWhite;
  DrawTextCentered(startX, startY, startX + width, startY + height, text);
end;

function FindEmptyPosition(botIndex: integer): Point;
var
  placementAttempts: integer;
begin
  placementAttempts := 0;
  repeat
    Result.X := Random(FIELD_WIDTH);
    Result.Y := Random(FIELD_HEIGHT);
    Inc(placementAttempts);
    if placementAttempts > 1000 then
    begin
      Result.X := -1;
      Result.Y := -1;
      exit;
    end;
  until botFields[botIndex, Result.X, Result.Y] = Empty;
end;

/// Возвращает случайную клетку заданного типа на поле бота или (-1, -1),
/// если таких клеток нет. Равномерный выбор за один проход (резервуарная
/// выборка), поэтому собирать список координат не нужно.
function FindCellOfType(botIndex: integer; wanted: CellType): Point;
var
  seen: integer;
begin
  Result := Point.Create(-1, -1);
  seen := 0;
  for var x := 0 to FIELD_WIDTH - 1 do
    for var y := 0 to FIELD_HEIGHT - 1 do
      if botFields[botIndex, x, y] = wanted then
      begin
        Inc(seen);
        if Random(seen) = 0 then
          Result := Point.Create(x, y);
      end;
end;

/// Кладёт яблоко в случайную свободную клетку поля бота.
/// Возвращает False, если свободного места не нашлось.
function PlaceApple(botIndex: integer): boolean;
begin
  var position := FindEmptyPosition(botIndex);
  Result := (position.X >= 0) and (position.Y >= 0);
  if Result then
  begin
    botFields[botIndex, position.X, position.Y] := Apple;
    botAppleCount[botIndex] += 1;
  end;
end;

function GetFrontPosition(x, y, direction: integer): Point;
begin
  case direction of
    0: Result := Point.Create(x, (y - 1 + FIELD_HEIGHT) mod FIELD_HEIGHT);
    1: Result := Point.Create((x + 1) mod FIELD_WIDTH, y);
    2: Result := Point.Create(x, (y + 1) mod FIELD_HEIGHT);
    3: Result := Point.Create((x - 1 + FIELD_WIDTH) mod FIELD_WIDTH, y);
  end;
end;

function FindBotAtPosition(botIndex, x, y: integer): integer;
begin
  if bots[botIndex].active and (bots[botIndex].x = x) and (bots[botIndex].y = y) then
    Result := botIndex
  else
    Result := -1;
end;

function MinimumValue(const data: array of real): real;
var
  index: integer;
begin
  if Length(data) = 0 then
    raise Exception.Create('Массив пуст');
  Result := data[0];
  for index := 1 to High(data) do
    if data[index] < Result then
      Result := data[index];
end;

function MaximumValue(const data: array of real): real;
var
  index: integer;
begin
  if Length(data) = 0 then
    raise Exception.Create('Массив пуст');
  Result := data[0];
  for index := 1 to High(data) do
    if data[index] > Result then
      Result := data[index];
end;

procedure InitializeDSU(var dsu: DisjointSetUnion);
var
  index: integer;
begin
  for index := 0 to FIELD_WIDTH * FIELD_HEIGHT - 1 do
  begin
    dsu.parent[index] := index;
    dsu.rank[index] := 0;
  end;
end;

function FindDSU(var dsu: DisjointSetUnion; x: integer): integer;
begin
  if dsu.parent[x] <> x then
    dsu.parent[x] := FindDSU(dsu, dsu.parent[x]);
  Result := dsu.parent[x];
end;

procedure UnionDSU(var dsu: DisjointSetUnion; x, y: integer);
var
  parentX, parentY: integer;
begin
  parentX := FindDSU(dsu, x);
  parentY := FindDSU(dsu, y);
  if parentX = parentY then exit;
  if dsu.rank[parentX] < dsu.rank[parentY] then
    dsu.parent[parentX] := parentY
  else if dsu.rank[parentX] > dsu.rank[parentY] then
    dsu.parent[parentY] := parentX
  else
  begin
    dsu.parent[parentY] := parentX;
    dsu.rank[parentX] += 1;
  end;
end;

/// Снимает бота с поля. Счётчик живых уменьшается ровно один раз:
/// повторный вызов для уже погибшего бота ничего не делает.
procedure KillBot(botIndex: integer; var bot: Bot);
begin
  if not bot.active then exit;
  bot.active := false;
  botFields[botIndex, bot.x, bot.y] := Empty;
  Dec(activeBotCount);
end;

procedure ExecuteCommand(botIndex: integer; var bot: Bot);
var
  frontPosition, leftPosition, rightPosition: Point;
begin
  if bot.actionCount >= MAXIMUM_ACTIONS then
  begin
    KillBot(botIndex, bot);
    exit;
  end;
  
  // Ген хранит число 0..GENOME_LENGTH-1; команда — остаток от деления на
  // число команд. Одно и то же значение служит и командой, и смещением
  // перехода, поэтому мутация гена осмысленна в обеих ролях.
  case bot.genome[bot.genomePosition] mod COMMAND_COUNT of
    0:
      begin
        frontPosition := GetFrontPosition(bot.x, bot.y, bot.direction);
        case botFields[botIndex, frontPosition.X, frontPosition.Y] of
          Empty:
            begin
              botFields[botIndex, bot.x, bot.y] := Empty;
              bot.x := frontPosition.X;
              bot.y := frontPosition.Y;
              botFields[botIndex, bot.x, bot.y] := BotCell;
              if not bot.visited[bot.x, bot.y] then
              begin
                bot.visited[bot.x, bot.y] := true;
                bot.fitness += FITNESS_NEW_CELL;
              end;
            end;
          Apple:
            begin
              botFields[botIndex, bot.x, bot.y] := Empty;
              bot.x := frontPosition.X;
              bot.y := frontPosition.Y;
              botFields[botIndex, bot.x, bot.y] := BotCell;
              bot.fitness += FITNESS_APPLE;
              botAppleCount[botIndex] -= 1;
              PlaceApple(botIndex);
              if not bot.visited[bot.x, bot.y] then
              begin
                bot.visited[bot.x, bot.y] := true;
                bot.fitness += FITNESS_NEW_CELL;
              end;
            end;
          Poison:
            begin
              // Раньше эта ветка посимвольно совпадала с Empty: яд молча
              // стирался, штрафа не было, да ещё и начислялся плюс за новую
              // клетку. Отличать яд от пустоты эволюции было незачем, и весь
              // сенсорный аппарат команды 4 оставался бесполезен.
              botFields[botIndex, bot.x, bot.y] := Empty;
              bot.x := frontPosition.X;
              bot.y := frontPosition.Y;
              bot.actionCount += 1;
              KillBot(botIndex, bot);
              exit;
            end;
        end;
        bot.genomePosition := (bot.genomePosition + 1) mod GENOME_LENGTH;
      end;
    1:
      begin
        // Награды за поворот здесь быть не должно. Пока она была, геном из
        // одних поворотов набирал полный лимит очков, ничего не делая и
        // ничем не рискуя, и вытеснял из элиты любую осмысленную стратегию.
        bot.direction := (bot.direction + 1) mod 4;
        bot.genomePosition := (bot.genomePosition + 1) mod GENOME_LENGTH;
      end;
    2:
      begin
        bot.direction := (bot.direction - 1 + 4) mod 4;
        bot.genomePosition := (bot.genomePosition + 1) mod GENOME_LENGTH;
      end;
    3:
      begin
        frontPosition := GetFrontPosition(bot.x, bot.y, bot.direction);
        if botFields[botIndex, frontPosition.X, frontPosition.Y] = Poison then
        begin
          botFields[botIndex, frontPosition.X, frontPosition.Y] := Empty;
          bot.fitness += FITNESS_KILL_POISON;
          PlaceApple(botIndex);
        end;
        bot.genomePosition := (bot.genomePosition + 1) mod GENOME_LENGTH;
      end;
    4:
      begin
        // Сенсор. Раньше переход шёл на абсолютный адрес 0..3, поэтому всё
        // ветвление упиралось в первые клетки генома, а ветки "яблоко
        // впереди" и "ничего не найдено" давали один и тот же адрес и были
        // неразличимы. Теперь ситуация выбирает элемент таблицы переходов,
        // лежащей в следующих SENSOR_SITUATIONS генах, а сам переход
        // относительный.
        frontPosition := GetFrontPosition(bot.x, bot.y, bot.direction);
        leftPosition := GetFrontPosition(bot.x, bot.y, (bot.direction - 1 + 4) mod 4);
        rightPosition := GetFrontPosition(bot.x, bot.y, (bot.direction + 1) mod 4);

        var situation: integer;
        if botFields[botIndex, frontPosition.X, frontPosition.Y] = Apple then
          situation := 0
        else if botFields[botIndex, frontPosition.X, frontPosition.Y] = Poison then
          situation := 1
        else if botFields[botIndex, frontPosition.X, frontPosition.Y] = Wall then
          situation := 2
        else if botFields[botIndex, leftPosition.X, leftPosition.Y] = Apple then
          situation := 3
        else if botFields[botIndex, rightPosition.X, rightPosition.Y] = Apple then
          situation := 4
        else
          situation := 5;

        var offset := bot.genome[(bot.genomePosition + 1 + situation) mod GENOME_LENGTH];
        bot.genomePosition := (bot.genomePosition + offset) mod GENOME_LENGTH;
      end;
    5:
      begin
        // Безусловный относительный переход. Раньше адрес брался как
        // genome[...] mod GENOME_LENGTH, но гены хранили только 0..5,
        // поэтому попасть можно было лишь в первые шесть клеток генома.
        var offset := bot.genome[(bot.genomePosition + 1) mod GENOME_LENGTH];
        bot.genomePosition := (bot.genomePosition + offset) mod GENOME_LENGTH;
      end;
  end;
  
  bot.actionCount += 1;
end;

procedure Crossover(parent1, parent2: Bot; var child1, child2: Bot);
var
  crossoverPoint1, crossoverPoint2, index: integer;
begin
  crossoverPoint1 := Random(GENOME_LENGTH - 1) + 1;
  crossoverPoint2 := Random(GENOME_LENGTH - crossoverPoint1) + crossoverPoint1;
  for index := 0 to GENOME_LENGTH - 1 do
  begin
    if (index < crossoverPoint1) or (index >= crossoverPoint2) then
    begin
      child1.genome[index] := parent1.genome[index];
      child2.genome[index] := parent2.genome[index];
    end
    else
    begin
      child1.genome[index] := parent2.genome[index];
      child2.genome[index] := parent1.genome[index];
    end;
  end;
end;

procedure Initialize;
var
  rowIndex, colIndex, botIndex: integer;
begin
  // Фиксированное зерно делает прогон воспроизводимым: два запуска дают
  // одинаковый CSV, и упавший или интересный прогон можно повторить.
  if RANDOM_SEED <> 0 then
    Randomize(RANDOM_SEED)
  else
    Randomize;

  try
    Assign(logFile, 'gen_bots_log.csv');
    Rewrite(logFile);
    Writeln(logFile, 'generation;avg_fitness;max_fitness;mutation_rate;apples;walls;duration_ms');
    isLogOpen := True;
  except
    // Журнал не критичен: если файл занят или недоступен, симуляция идёт без него
    isLogOpen := False;
  end;

  SetWindowTitle('Генетические боты');
  SetWindowSize(WINDOW_WIDTH, WINDOW_HEIGHT);
  CenterWindow;
  LockDrawing;

  SetLength(generationDurations, historySegmentCount);
  SetLength(averageFitnessHistory, historySegmentCount);
  for rowIndex := 0 to historySegmentCount - 1 do
  begin
    generationDurations[rowIndex] := 0;
    averageFitnessHistory[rowIndex] := 0;
  end;
  
  ResetField;
  // Позиции ботов и метки BotCell на полях уже расставлены в ResetField.
  // Трогать их здесь нельзя: координаты разъедутся с содержимым полей.
  var direction := Random(4);
  for botIndex := 0 to MAXIMUM_BOTS - 1 do
  begin
    bots[botIndex].direction := direction;
    bots[botIndex].genomePosition := 0;
    bots[botIndex].actionCount := 0;
    bots[botIndex].fitness := 0;
    for rowIndex := 0 to FIELD_WIDTH - 1 do
      for colIndex := 0 to FIELD_HEIGHT - 1 do
        bots[botIndex].visited[rowIndex, colIndex] := false;
    // Заплатки "дослать недостающие команды" здесь больше нет: она могла
    // затереть единственное вхождение другой команды, а её проверка этого
    // уже не замечала. При декодировании по остатку любая команда
    // достижима из любого значения гена, и в геноме из 64 генов все шесть
    // команд присутствуют практически наверняка.
    for colIndex := 0 to GENOME_LENGTH - 1 do
      bots[botIndex].genome[colIndex] := Random(GENOME_LENGTH);
  end;
  
  DrawRectangledText(WINDOW_WIDTH div 2 - 150, WINDOW_HEIGHT div 2 - 20, 300, 40, 'Ожидайте стабилизации графика...');
  Redraw;
  generationStartTime := Milliseconds;
end;

procedure AddGenerationDuration(newDuration: real);
var
  index: integer;
begin
  for index := generationDurations.Length - 1 downto 1 do
    generationDurations[index] := generationDurations[index - 1];
  generationDurations[0] := newDuration;
end;

procedure AddAverageFitness(newFitness: real);
var
  index: integer;
begin
  for index := averageFitnessHistory.Length - 1 downto 1 do
    averageFitnessHistory[index] := averageFitnessHistory[index - 1];
  averageFitnessHistory[0] := newFitness;
  if historyFilled < historySegmentCount then
    Inc(historyFilled);
end;

/// Дописывает строку журнала. Прогон при фиксированном зерне
/// воспроизводим, поэтому CSV можно сравнивать между запусками.
procedure LogGeneration(durationMs: real);
begin
  if not isLogOpen then exit;
  Writeln(logFile,
    generationNumber, ';',
    averageFitnessHistory[0].ToString('F2'), ';',
    currentMaximumFitness, ';',
    currentMutationRate.ToString('F4'), ';',
    currentAppleCount, ';',
    currentWallCount, ';',
    Round(durationMs));
  Flush(logFile);
end;

procedure UpdateStatus;
begin
  SetWindowTitle('GenBots | поколение ' + generationNumber.ToString +
                 ' | живых ' + activeBotCount.ToString +
                 ' | средняя ' + averageFitnessHistory[0].ToString('F1') +
                 ' | мутация ' + currentMutationRate.ToString('F3'));
end;

procedure CreateNewPopulation;
var
  survivorIndices: array of integer;
  newBots: array[0..MAXIMUM_BOTS - 1] of Bot;
  newBotIndex, rowIndex, colIndex: integer;
  totalFitness: integer;
  eliteIndices: array[0..ELITE_BOT_COUNT - 1] of integer;
  currentAverageFitness: real;
begin
  currentAverageFitness := 0;
  currentMaximumFitness := bots[0].fitness;
  for rowIndex := 0 to MAXIMUM_BOTS - 1 do
  begin
    currentAverageFitness += bots[rowIndex].fitness;
    if bots[rowIndex].fitness > currentMaximumFitness then
      currentMaximumFitness := bots[rowIndex].fitness;
  end;
  currentAverageFitness := currentAverageFitness / MAXIMUM_BOTS;
  
  AddAverageFitness(currentAverageFitness);
  
  // Мутация и сложность среды пересматриваются раз в
  // ENVIRONMENT_ADAPT_INTERVAL поколений, по среднему за окно. Раньше это
  // делалось каждое поколение, и контур управления реагировал на
  // собственные действия: добавление десяти стен роняло среднюю
  // приспособленность, падение засчитывалось как стагнация и поднимало
  // мутацию, хотя популяция не деградировала — усложнилась задача.
  windowFitnessSum += currentAverageFitness;
  Inc(windowGenerations);
  if windowGenerations >= ENVIRONMENT_ADAPT_INTERVAL then
  begin
    var windowAverage := windowFitnessSum / windowGenerations;

    if windowAverage <= previousWindowAverage then
    begin
      stagnationCounter += 1;
      if stagnationCounter >= STAGNATION_THRESHOLD then
        currentMutationRate := Minimum(BASE_MUTATION_RATE + (stagnationCounter - STAGNATION_THRESHOLD + 1) * MUTATION_INCREMENT, MAXIMUM_MUTATION_RATE);
    end
    else
    begin
      stagnationCounter := 0;
      if currentMutationRate > BASE_MUTATION_RATE then
        currentMutationRate := Maximum(currentMutationRate - MUTATION_DECREMENT, BASE_MUTATION_RATE);
    end;
    previousWindowAverage := windowAverage;

    // Гистерезис: усложняем выше порога, упрощаем сильно ниже него, между
    // ними среда не трогается. Иначе сложность колеблется туда-сюда.
    if windowAverage > FITNESS_THRESHOLD then
    begin
      if currentAppleCount > MINIMUM_APPLES then
        currentAppleCount -= 1;
      if currentWallCount < MAXIMUM_WALLS then
        currentWallCount += 10;
    end
    else if windowAverage < FITNESS_THRESHOLD / 2 then
    begin
      if currentAppleCount < INITIAL_APPLES then
        currentAppleCount += 1;
      if currentWallCount > INITIAL_WALLS then
        currentWallCount -= 10;
    end;

    windowFitnessSum := 0;
    windowGenerations := 0;
  end;
  
  SetLength(survivorIndices, MAXIMUM_BOTS);
  for rowIndex := 0 to MAXIMUM_BOTS - 1 do
    survivorIndices[rowIndex] := rowIndex;
  
  var eliteCopiedCount := 0;
  var direction := Random(4);
  var position := FindEmptyPosition(0);
  for rowIndex := 0 to ELITE_BOT_COUNT - 1 do
  begin
    if Length(survivorIndices) = 0 then break;
    var maxFitnessIndex := survivorIndices[0];
    for colIndex := 1 to High(survivorIndices) do
      if bots[survivorIndices[colIndex]].fitness > bots[maxFitnessIndex].fitness then
        maxFitnessIndex := survivorIndices[colIndex];
    eliteIndices[rowIndex] := maxFitnessIndex;
    newBots[eliteCopiedCount] := bots[maxFitnessIndex];
    newBots[eliteCopiedCount].x := position.X;
    newBots[eliteCopiedCount].y := position.Y;
    newBots[eliteCopiedCount].direction := direction;
    newBots[eliteCopiedCount].genomePosition := 0;
    newBots[eliteCopiedCount].actionCount := 0;
    newBots[eliteCopiedCount].fitness := 0;
    for colIndex := 0 to FIELD_WIDTH - 1 do
      for var tempIndex := 0 to FIELD_HEIGHT - 1 do
        newBots[eliteCopiedCount].visited[colIndex, tempIndex] := false;
    Inc(eliteCopiedCount);
    for colIndex := 0 to High(survivorIndices) do
      if survivorIndices[colIndex] = maxFitnessIndex then
      begin
        survivorIndices[colIndex] := survivorIndices[High(survivorIndices)];
        SetLength(survivorIndices, Length(survivorIndices) - 1);
        break;
      end;
  end;
  
  newBotIndex := eliteCopiedCount;
  totalFitness := 0;
  for rowIndex := 0 to High(survivorIndices) do
    totalFitness += bots[survivorIndices[rowIndex]].fitness + 1;
  
  if totalFitness = 0 then totalFitness := 1;
  
  while newBotIndex < MAXIMUM_BOTS do
  begin
    var parent1, parent2: integer;
    if Length(survivorIndices) > 0 then
    begin
      var randomFitness1 := Random(totalFitness);
      var fitnessSum := 0;
      parent1 := survivorIndices[0];
      for rowIndex := 0 to High(survivorIndices) do
      begin
        fitnessSum += bots[survivorIndices[rowIndex]].fitness + 1;
        if fitnessSum >= randomFitness1 then
        begin
          parent1 := survivorIndices[rowIndex];
          break;
        end;
      end;
      var randomFitness2 := Random(totalFitness);
      fitnessSum := 0;
      parent2 := survivorIndices[0];
      for rowIndex := 0 to High(survivorIndices) do
      begin
        fitnessSum += bots[survivorIndices[rowIndex]].fitness + 1;
        if fitnessSum >= randomFitness2 then
        begin
          parent2 := survivorIndices[rowIndex];
          break;
        end;
      end;
    end
    else
    begin
      parent1 := eliteIndices[Random(eliteCopiedCount)];
      parent2 := eliteIndices[Random(eliteCopiedCount)];
    end;
    
    var child1, child2: Bot;
    Crossover(bots[parent1], bots[parent2], child1, child2);
    
    for colIndex := 0 to GENOME_LENGTH - 1 do
    begin
      if Random < currentMutationRate then
        child1.genome[colIndex] := Random(GENOME_LENGTH);
      if Random < currentMutationRate then
        child2.genome[colIndex] := Random(GENOME_LENGTH);
    end;
    
    if newBotIndex < MAXIMUM_BOTS then
    begin
      newBots[newBotIndex] := child1;
      newBots[newBotIndex].x := position.X;
      newBots[newBotIndex].y := position.Y;
      newBots[newBotIndex].direction := direction;
      newBots[newBotIndex].genomePosition := 0;
      newBots[newBotIndex].actionCount := 0;
      newBots[newBotIndex].fitness := 0;
      for colIndex := 0 to FIELD_WIDTH - 1 do
        for var tempIndex := 0 to FIELD_HEIGHT - 1 do
          newBots[newBotIndex].visited[colIndex, tempIndex] := false;
      Inc(newBotIndex);
    end;
    if newBotIndex < MAXIMUM_BOTS then
    begin
      newBots[newBotIndex] := child2;
      newBots[newBotIndex].x := position.X;
      newBots[newBotIndex].y := position.Y;
      newBots[newBotIndex].direction := direction;
      newBots[newBotIndex].genomePosition := 0;
      newBots[newBotIndex].actionCount := 0;
      newBots[newBotIndex].fitness := 0;
      for colIndex := 0 to FIELD_WIDTH - 1 do
        for var tempIndex := 0 to FIELD_HEIGHT - 1 do
          newBots[newBotIndex].visited[colIndex, tempIndex] := false;
      Inc(newBotIndex);
    end;
  end;
  
  for rowIndex := 0 to MAXIMUM_BOTS - 1 do
  begin
    bots[rowIndex] := newBots[rowIndex];
    bots[rowIndex].active := true;
  end;
end;

procedure ResetField;
var
  rowIndex, colIndex, botIndex: integer;
  tempField: array[0..FIELD_WIDTH - 1, 0..FIELD_HEIGHT - 1] of CellType;
  emptyCells: array of Point;
  emptyCount: integer;
  visited: array[0..FIELD_WIDTH - 1, 0..FIELD_HEIGHT - 1] of boolean;
  // Очередь BFS предвыделяется на всё поле и работает через индексы
  // head/tail: извлечение и добавление за O(1) вместо сдвига массива.
  queue: array[0..FIELD_WIDTH * FIELD_HEIGHT - 1] of Point;
  queueHead, queueTail: integer;

  procedure UpdateEmptyCells(idx: integer);
  begin
    emptyCells[idx] := emptyCells[emptyCount - 1];
    Dec(emptyCount);
  end;

  /// Случайная свободная клетка в подготавливаемом поле, или (-1, -1)
  function FindEmptyInTemp: Point;
  var
    attempts: integer;
  begin
    attempts := 0;
    repeat
      Result := Point.Create(Random(FIELD_WIDTH), Random(FIELD_HEIGHT));
      Inc(attempts);
      if attempts > 1000 then
      begin
        Result := Point.Create(-1, -1);
        exit;
      end;
    until tempField[Result.X, Result.Y] = Empty;
  end;

  function IsValidMove(x, y: integer): boolean;
  begin
    Result := (x >= 0) and (x < FIELD_WIDTH) and 
              (y >= 0) and (y < FIELD_HEIGHT) and
              (tempField[x, y] <> Wall);
  end;

  function WillCreateEnclosure(x, y: integer): boolean;
  var
    i, count: integer;
    p: Point;
  begin
    Result := false;
    tempField[x, y] := Wall; // Временно ставим стену

    // Инициализация visited
    for i := 0 to FIELD_WIDTH - 1 do
      for var colIndex := 0 to FIELD_HEIGHT - 1 do
        visited[i, colIndex] := false;

    queueHead := 0;
    queueTail := 0;
    // Находим первую пустую клетку рядом
    var startX := -1;
    var startY := -1;
    var directions: array[0..3] of Point = (
      Point.Create(0, -1), Point.Create(0, 1),
      Point.Create(-1, 0), Point.Create(1, 0)
    );
    for i := 0 to 3 do
    begin
      var nx := x + directions[i].X;
      var ny := y + directions[i].Y;
      if IsValidMove(nx, ny) then
      begin
        startX := nx;
        startY := ny;
        Break;
      end;
    end;

    if startX = -1 then
    begin
      tempField[x, y] := Empty;
      Result := true; // Нет доступных клеток рядом
      Exit;
    end;

    // BFS для подсчета достижимых клеток
    queue[queueTail] := Point.Create(startX, startY);
    Inc(queueTail);
    visited[startX, startY] := true;
    count := 1;

    while queueHead < queueTail do
    begin
      p := queue[queueHead];
      Inc(queueHead);

      for i := 0 to 3 do
      begin
        var newX := p.X + directions[i].X;
        var newY := p.Y + directions[i].Y;
        if IsValidMove(newX, newY) and not visited[newX, newY] then
        begin
          visited[newX, newY] := true;
          Inc(count);
          queue[queueTail] := Point.Create(newX, newY);
          Inc(queueTail);
        end;
      end;
    end;

    // Подсчет всех пустых клеток
    var totalEmpty := 0;
    for i := 1 to FIELD_WIDTH - 2 do
      for var colIndex := 1 to FIELD_HEIGHT - 2 do
        if tempField[i, colIndex] <> Wall then
          Inc(totalEmpty);

    tempField[x, y] := Empty; // Возвращаем клетку
    Result := count < totalEmpty; // Замкнутость, если не все клетки достижимы
  end;

begin
  // Инициализация поля
  for rowIndex := 0 to FIELD_WIDTH - 1 do
    for colIndex := 0 to FIELD_HEIGHT - 1 do
      tempField[rowIndex, colIndex] := Empty;

  // Установка границ
  for rowIndex := 0 to FIELD_WIDTH - 1 do
  begin
    tempField[rowIndex, 0] := Wall;
    tempField[rowIndex, FIELD_HEIGHT - 1] := Wall;
  end;
  for colIndex := 0 to FIELD_HEIGHT - 1 do
  begin
    tempField[0, colIndex] := Wall;
    tempField[FIELD_WIDTH - 1, colIndex] := Wall;
  end;

  // Собираем список пустых клеток
  emptyCount := 0;
  SetLength(emptyCells, (FIELD_WIDTH - 2) * (FIELD_HEIGHT - 2));
  for rowIndex := 1 to FIELD_WIDTH - 2 do
    for colIndex := 1 to FIELD_HEIGHT - 2 do
    begin
      emptyCells[emptyCount] := Point.Create(rowIndex, colIndex);
      Inc(emptyCount);
    end;

  // Размещение стен
  var wallsToPlace := currentWallCount;
  var wallsPlaced := 0;
  while (wallsPlaced < wallsToPlace) and (emptyCount > 0) do
  begin
    var idx := Random(emptyCount);
    var x := emptyCells[idx].X;
    var y := emptyCells[idx].Y;

    if not WillCreateEnclosure(x, y) then
    begin
      tempField[x, y] := Wall;
      Inc(wallsPlaced);
      UpdateEmptyCells(idx);
    end else
    begin
      UpdateEmptyCells(idx); // Удаляем клетку, даже если стена не поставлена
    end;
  end;

  // Одна раскладка на всё поколение. Раньше стартовая клетка и позиции
  // всех яблок и яда разыгрывались отдельно для каждого бота: 128 ботов
  // проходили 128 разных испытаний, а их приспособленности сравнивались
  // напрямую в отборе. Дисперсия среды при этом сопоставима с разницей
  // между хорошим и плохим геномом, то есть отбор шёл по шуму.
  var startPosition := FindEmptyInTemp;
  if startPosition.X < 0 then
    startPosition := Point.Create(FIELD_WIDTH div 2, FIELD_HEIGHT div 2);
  tempField[startPosition.X, startPosition.Y] := BotCell;

  var placedApples := 0;
  for rowIndex := 1 to currentAppleCount do
  begin
    var applePosition := FindEmptyInTemp;
    if applePosition.X < 0 then break;
    tempField[applePosition.X, applePosition.Y] := Apple;
    Inc(placedApples);
  end;
  for rowIndex := 1 to POISON_COUNT do
  begin
    var poisonPosition := FindEmptyInTemp;
    if poisonPosition.X < 0 then break;
    tempField[poisonPosition.X, poisonPosition.Y] := Poison;
  end;

  // Копирование готовой раскладки всем ботам
  for botIndex := 0 to MAXIMUM_BOTS - 1 do
  begin
    for rowIndex := 0 to FIELD_WIDTH - 1 do
      for colIndex := 0 to FIELD_HEIGHT - 1 do
        botFields[botIndex, rowIndex, colIndex] := tempField[rowIndex, colIndex];
    bots[botIndex].x := startPosition.X;
    bots[botIndex].y := startPosition.Y;
    bots[botIndex].active := true;
    botAppleCount[botIndex] := placedApples;
  end;
end;

/// Рисует одну серию в своём собственном масштабе. Общий масштаб для
/// приспособленности (очки) и длительности поколения (миллисекунды) делал
/// вторую кривую нечитаемой: она прижималась к нижнему краю.
procedure RenderSeries(data: array of real; count, xLeft, yTop, width, height: integer;
                       lineColor: Color; drawPoints: boolean);
var
  index: integer;
  minValue, maxValue, scaleX, scaleY: real;

  function PointX(i: integer): integer;
  begin
    // Индекс 0 — самое свежее поколение, поэтому время идёт слева направо
    if count > 1 then
      Result := Round(xLeft + width - i * scaleX)
    else
      Result := xLeft + width;
  end;

  function PointY(i: integer): integer;
  begin
    if scaleY = 0 then
      Result := Round(yTop + height / 2)
    else
      Result := Round(yTop + height - (data[i] - minValue) * scaleY);
  end;

begin
  if count < 1 then exit;
  minValue := data[0];
  maxValue := data[0];
  for index := 1 to count - 1 do
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
  for index := 1 to count - 1 do
    LineTo(PointX(index), PointY(index));

  if drawPoints then
  begin
    Brush.Color := lineColor;
    Pen.Color := lineColor;
    for index := 0 to count - 1 do
      FillCircle(PointX(index), PointY(index), 2);
  end;
end;

procedure RenderGraph(xLeft, yTop, width, height: integer);
var
  index: integer;
  averageFitness, minFitness, maxFitness: real;
begin
  ClearWindow(emptyCellColor);
  if historyFilled = 0 then
  begin
    DrawRectangledText(WINDOW_WIDTH div 2 - 150, WINDOW_HEIGHT div 2 - 20, 300, 40,
                       'Идёт первое поколение...');
    Redraw;
    exit;
  end;

  Pen.Color := clLightGray;
  Pen.Width := 1;
  for index := 1 to 4 do
  begin
    Line(xLeft, Round(yTop + index * height / 5), xLeft + width, Round(yTop + index * height / 5));
    Line(Round(xLeft + index * width / 5), yTop, Round(xLeft + index * width / 5), yTop + height);
  end;

  // Считается только заполненная часть истории: незаполненные нули
  // раньше занижали минимум и среднее все первые сто поколений.
  RenderSeries(generationDurations, historyFilled, xLeft, yTop, width, height, clCyan, false);
  RenderSeries(averageFitnessHistory, historyFilled, xLeft, yTop, width, height, clYellow, true);

  minFitness := averageFitnessHistory[0];
  maxFitness := averageFitnessHistory[0];
  averageFitness := 0;
  for index := 0 to historyFilled - 1 do
  begin
    if averageFitnessHistory[index] < minFitness then minFitness := averageFitnessHistory[index];
    if averageFitnessHistory[index] > maxFitness then maxFitness := averageFitnessHistory[index];
    averageFitness += averageFitnessHistory[index];
  end;
  averageFitness /= historyFilled;

  var graphInfo := 'Поколение ' + generationNumber.ToString +
                   '   мутация ' + currentMutationRate.ToString('F3') + newline +
                   'Приспособленность (жёлтая): макс ' + maxFitness.ToString('F1') +
                   ', мин ' + minFitness.ToString('F1') + newline +
                   'средняя за историю ' + averageFitness.ToString('F1') + newline +
                   'Длительность поколения (голубая), своя шкала';
  DrawRectangledText(WINDOW_WIDTH div 2 - 160, WINDOW_HEIGHT - 92, 320, 84, graphInfo);
  Redraw;
end;

procedure Update;
var
  rowIndex: integer;
begin
  for var botIndex := 0 to MAXIMUM_BOTS - 1 do
  begin
    if botAppleCount[botIndex] < MINIMUM_APPLES then
      PlaceApple(botIndex);

    // Сколько яблок распадётся в яд на этом такте. Розыгрыш идёт по числу
    // яблок (порядка 30), а не по всем 900 клеткам поля; сканировать поле
    // приходится только когда распад действительно случился — примерно
    // в 3% тактов.
    var decayCount := 0;
    for var apple := 1 to botAppleCount[botIndex] do
      if Random < APPLE_DECAY_PROBABILITY then
        Inc(decayCount);

    while decayCount > 0 do
    begin
      var position := FindCellOfType(botIndex, Apple);
      if (position.X < 0) or (position.Y < 0) then break;
      botFields[botIndex, position.X, position.Y] := Poison;
      botAppleCount[botIndex] -= 1;
      Dec(decayCount);
    end;
  end;
  
  rowIndex := 0;
  while rowIndex < MAXIMUM_BOTS do
  begin
    if bots[rowIndex].active then
    begin
      // За такт бот выполняет служебные команды (повороты, переходы,
      // проверки) до первой команды движения, но не больше maximumThinkTime
      // штук. Гибель обрывает такт немедленно: снятие с поля и уменьшение
      // счётчика живых делает KillBot, поэтому отдельной проверки лимита
      // действий здесь больше нет.
      var remainingCommands := maximumThinkTime - 1;
      while (remainingCommands > 0) and bots[rowIndex].active and
            (bots[rowIndex].genome[bots[rowIndex].genomePosition] mod COMMAND_COUNT <> 0) do
      begin
        ExecuteCommand(rowIndex, bots[rowIndex]);
        remainingCommands -= 1;
      end;
      if bots[rowIndex].active then
        ExecuteCommand(rowIndex, bots[rowIndex]);
      
      if activeBotCount <= 0 then
      begin
        CreateNewPopulation;
        ResetField;
        activeBotCount := MAXIMUM_BOTS;
        Inc(generationNumber);
        var generationDuration := Milliseconds - generationStartTime;
        AddGenerationDuration(generationDuration);
        generationStartTime := Milliseconds;
        LogGeneration(generationDuration);
        // Заголовок окна обновляется здесь, а не в главном цикле:
        // SetWindowTitle маршалит вызов в поток окна и стоит дорого.
        UpdateStatus;
        if generationNumber > skipRenderGenerations then
          if viewMode = ViewGraph then
            RenderGraph(12, 12, WINDOW_WIDTH - 24, WINDOW_HEIGHT - 120);
        exit;
      end;
    end;
    Inc(rowIndex);
  end;
end;

procedure Render;
var
  rowIndex, colIndex, botIndex: integer;
  visitedCells: array[0..FIELD_WIDTH - 1, 0..FIELD_HEIGHT - 1] of boolean;
begin
  ClearWindow(emptyCellColor);
  for rowIndex := 0 to FIELD_WIDTH - 1 do
    for colIndex := 0 to FIELD_HEIGHT - 1 do
    begin
      renderField[rowIndex, colIndex] := botFields[0, rowIndex, colIndex];
      visitedCells[rowIndex, colIndex] := false;
      var hasApple := false;
      var hasPoison := false;
      for botIndex := 0 to MAXIMUM_BOTS - 1 do
      begin
        if botFields[botIndex, rowIndex, colIndex] = Apple then hasApple := true;
        if botFields[botIndex, rowIndex, colIndex] = Poison then hasPoison := true;
        if bots[botIndex].visited[rowIndex, colIndex] then visitedCells[rowIndex, colIndex] := true;
      end;
      if hasApple then renderField[rowIndex, colIndex] := Apple
      else if hasPoison then renderField[rowIndex, colIndex] := Poison;
    end;
  
  for rowIndex := 0 to FIELD_WIDTH - 1 do
    for colIndex := 0 to FIELD_HEIGHT - 1 do
      case renderField[rowIndex, colIndex] of
        Wall:
          begin
            Brush.Color := wallColor;
            FillRect(rowIndex * PIXEL_SIZE, colIndex * PIXEL_SIZE, (rowIndex + 1) * PIXEL_SIZE, (colIndex + 1) * PIXEL_SIZE);
          end;
        Apple:
          begin
            Brush.Color := appleColor;
            FillCircle(rowIndex * PIXEL_SIZE + PIXEL_SIZE div 2, colIndex * PIXEL_SIZE + PIXEL_SIZE div 2, PIXEL_SIZE div 4);
          end;
        Poison:
          begin
            Brush.Color := poisonColor;
            FillCircle(rowIndex * PIXEL_SIZE + PIXEL_SIZE div 2, colIndex * PIXEL_SIZE + PIXEL_SIZE div 2, PIXEL_SIZE div 4);
          end;
      end;
  
  for rowIndex := 0 to FIELD_WIDTH - 1 do
    for colIndex := 0 to FIELD_HEIGHT - 1 do
      if visitedCells[rowIndex, colIndex] then
      begin
        Brush.Color := ARGB(128, 255, 255, 0);
        FillRect(rowIndex * PIXEL_SIZE, colIndex * PIXEL_SIZE, (rowIndex + 1) * PIXEL_SIZE, (colIndex + 1) * PIXEL_SIZE);
      end;
  
  for botIndex := 0 to MAXIMUM_BOTS - 1 do
  begin
    if bots[botIndex].active then
    begin
      rowIndex := bots[botIndex].x;
      colIndex := bots[botIndex].y;
      Pen.Color := clCyan;
      Brush.Color := RGB(0, 255, 0);
      Rectangle(rowIndex * PIXEL_SIZE, colIndex * PIXEL_SIZE, (rowIndex + 1) * PIXEL_SIZE, (colIndex + 1) * PIXEL_SIZE);
    end;
  end;
  
  botIndex := -1;
  for rowIndex := 0 to MAXIMUM_BOTS - 1 do
    if FindBotAtPosition(rowIndex, MouseX div PIXEL_SIZE, MouseY div PIXEL_SIZE) >= 0 then
    begin
      botIndex := rowIndex;
      break;
    end;
  if botIndex >= 0 then
  begin
    var genomeString := '';
    for colIndex := 0 to GENOME_LENGTH - 1 do
      genomeString += bots[botIndex].genome[colIndex].ToString + ' ';
    DrawRectangledText(WINDOW_WIDTH div 2 - 100, WINDOW_HEIGHT - 100, 200, 80, genomeString);
  end;
  
  Redraw;
end;

procedure HandleInput;
begin
  // Реакция на фронт нажатия. Прежняя версия крутила пустой цикл, пока
  // клавиша удерживается: это жгло ядро и блокировало симуляцию.
  if IsKeyPressed(VK_SPACE) then
    isSimulationPaused := not isSimulationPaused;
  if IsKeyPressed(VK_G) then
    viewMode := ViewGraph;
  if IsKeyPressed(VK_F) then
    viewMode := ViewField;

  if MousePressed and not wasMousePressed then
    if viewMode = ViewField then
      viewMode := ViewGraph
    else
      viewMode := ViewField;
  wasMousePressed := MousePressed;
end;

begin
  Initialize;
  UpdateStatus;
  while true do
  begin
    HandleInput;
    if isSimulationPaused then
      // В паузе считать нечего — отдаём процессор системе вместо
      // прокрутки пустого цикла на полной скорости.
      Sleep(16)
    else
      Update;
    if generationNumber > skipRenderGenerations then
      if viewMode = ViewField then
        Render;
  end;
end.

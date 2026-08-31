uses GraphABC, DP_Control, DP_Interface;

const
  MAXIMUM_BOTS          = 128;
  MINIMUM_BOTS          = 32;
  GENOME_LENGTH         = 32;
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
  FITNESS_THRESHOLD     = 10;
  MINIMUM_APPLES        = 5;
  MAXIMUM_WALLS         = 360;

type
  CellType = (Empty, Wall, Apple, Poison, BotCell);
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
  isSimulationRendered: boolean := False;
  isSimulationPaused: boolean := False;
  skipRenderGenerations: integer := 0;
  emptyCellColor: Color := clGray;
  wallColor: Color := clBlack;
  appleColor: Color := clGreen;
  poisonColor: Color := clRed;
  previousAverageFitness: real := 0;
  stagnationCounter: integer := 0;
  currentMutationRate: real := BASE_MUTATION_RATE;
  currentAppleCount: integer := 30;
  currentWallCount: integer := 270;

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

procedure ExecuteCommand(botIndex: integer; var bot: Bot);
var
  frontPosition, leftPosition, rightPosition, farFrontPosition: Point;
  jumpTarget: integer;
  hasMoved: boolean;
begin
  if bot.actionCount >= MAXIMUM_ACTIONS then
  begin
    bot.active := false;
    botFields[botIndex, bot.x, bot.y] := Empty;
    exit;
  end;
  
  hasMoved := false;
  case bot.genome[bot.genomePosition] of
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
              hasMoved := true;
              if not bot.visited[bot.x, bot.y] then
              begin
                bot.visited[bot.x, bot.y] := true;
                bot.fitness += 1;
              end;
            end;
          Apple:
            begin
              botFields[botIndex, bot.x, bot.y] := Empty;
              bot.x := frontPosition.X;
              bot.y := frontPosition.Y;
              botFields[botIndex, bot.x, bot.y] := BotCell;
              bot.fitness += 6;
              var position := FindEmptyPosition(botIndex);
              if (position.X >= 0) and (position.Y >= 0) then
                botFields[botIndex, position.X, position.Y] := Apple;
              hasMoved := true;
              if not bot.visited[bot.x, bot.y] then
              begin
                bot.visited[bot.x, bot.y] := true;
                bot.fitness += 1;
              end;
            end;
          Poison:
            begin
              botFields[botIndex, bot.x, bot.y] := Empty;
              bot.x := frontPosition.X;
              bot.y := frontPosition.Y;
              botFields[botIndex, bot.x, bot.y] := BotCell;
              hasMoved := true;
              if not bot.visited[bot.x, bot.y] then
              begin
                bot.visited[bot.x, bot.y] := true;
                bot.fitness += 1;
              end;
            end;
        end;
        bot.genomePosition := (bot.genomePosition + 1) mod GENOME_LENGTH;
      end;
    1:
      begin
        bot.direction := (bot.direction + 1) mod 4;
        bot.genomePosition := (bot.genomePosition + 1) mod GENOME_LENGTH;
        bot.fitness += 1;
      end;
    2:
      begin
        bot.direction := (bot.direction - 1 + 4) mod 4;
        bot.genomePosition := (bot.genomePosition + 1) mod GENOME_LENGTH;
        bot.fitness += 1;
      end;
    3:
      begin
        frontPosition := GetFrontPosition(bot.x, bot.y, bot.direction);
        if botFields[botIndex, frontPosition.X, frontPosition.Y] = Poison then
        begin
          botFields[botIndex, frontPosition.X, frontPosition.Y] := Empty;
          bot.fitness += 3;
          var position := FindEmptyPosition(botIndex);
          if (position.X >= 0) and (position.Y >= 0) then
            botFields[botIndex, position.X, position.Y] := Apple;
          hasMoved := true;
        end;
        bot.genomePosition := (bot.genomePosition + 1) mod GENOME_LENGTH;
      end;
    4:
      begin
        frontPosition := GetFrontPosition(bot.x, bot.y, bot.direction);
        leftPosition := GetFrontPosition(bot.x, bot.y, (bot.direction - 1 + 4) mod 4);
        rightPosition := GetFrontPosition(bot.x, bot.y, (bot.direction + 1) mod 4);
        farFrontPosition.X := frontPosition.X;
        farFrontPosition.Y := frontPosition.Y;
        var isFarValid := true;
        case bot.direction of
          0: if frontPosition.Y = 0 then isFarValid := false else farFrontPosition.Y := frontPosition.Y - 1;
          1: if frontPosition.X = FIELD_WIDTH - 1 then isFarValid := false else farFrontPosition.X := frontPosition.X + 1;
          2: if frontPosition.Y = FIELD_HEIGHT - 1 then isFarValid := false else farFrontPosition.Y := frontPosition.Y + 1;
          3: if frontPosition.X = 0 then isFarValid := false else farFrontPosition.X := frontPosition.X - 1;
        end;
        
        if botFields[botIndex, frontPosition.X, frontPosition.Y] = Apple then
          jumpTarget := 0
        else if botFields[botIndex, leftPosition.X, leftPosition.Y] = Apple then
          jumpTarget := 2
        else if botFields[botIndex, rightPosition.X, rightPosition.Y] = Apple then
          jumpTarget := 1
        else if botFields[botIndex, frontPosition.X, frontPosition.Y] = Poison then
          jumpTarget := 3
        else if botFields[botIndex, leftPosition.X, leftPosition.Y] = Poison then
          jumpTarget := 2
        else if botFields[botIndex, rightPosition.X, rightPosition.Y] = Poison then
          jumpTarget := 1
        else if botFields[botIndex, frontPosition.X, frontPosition.Y] = Wall then
          jumpTarget := bot.genome[(bot.genomePosition + 1) mod GENOME_LENGTH]
        else if isFarValid and (botFields[botIndex, farFrontPosition.X, farFrontPosition.Y] = Apple) then
          jumpTarget := 0
        else
          jumpTarget := 0;
        bot.genomePosition := jumpTarget mod GENOME_LENGTH;
      end;
    5:
      begin
        bot.genomePosition := bot.genome[(bot.genomePosition + 1) mod GENOME_LENGTH] mod GENOME_LENGTH;
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
    for colIndex := 0 to GENOME_LENGTH - 1 do
      bots[botIndex].genome[colIndex] := Random(6);
    var commandsPresent: array[0..5] of boolean;
    for colIndex := 0 to GENOME_LENGTH - 1 do
      commandsPresent[bots[botIndex].genome[colIndex]] := true;
    for var command := 0 to 5 do
      if not commandsPresent[command] then
      begin
        var randomIndex := Random(GENOME_LENGTH);
        bots[botIndex].genome[randomIndex] := command;
      end;
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
end;

procedure UpdateStatus;
begin
  SetWindowTitle('GenBots | Gen: ' + generationNumber.ToString + ' | Alive: ' + activeBotCount.ToString);
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
  for rowIndex := 0 to MAXIMUM_BOTS - 1 do
    currentAverageFitness += bots[rowIndex].fitness;
  currentAverageFitness := currentAverageFitness / MAXIMUM_BOTS;
  
  AddAverageFitness(currentAverageFitness);
  
  if currentAverageFitness <= previousAverageFitness then
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
  previousAverageFitness := currentAverageFitness;
  
  if currentAverageFitness > FITNESS_THRESHOLD then
  begin
    if currentAppleCount > MINIMUM_APPLES then
      currentAppleCount -= 1;
    if currentWallCount < MAXIMUM_WALLS then
      currentWallCount += 10;
  end
  else
  begin
    if currentAppleCount < 30 then
      currentAppleCount += 1;
    if currentWallCount > 270 then
      currentWallCount -= 10;
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
        child1.genome[colIndex] := Random(6);
      if Random < currentMutationRate then
        child2.genome[colIndex] := Random(6);
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
  queue: array of Point;

  procedure UpdateEmptyCells(idx: integer);
  begin
    emptyCells[idx] := emptyCells[emptyCount - 1];
    Dec(emptyCount);
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

    SetLength(queue, 0);
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
    SetLength(queue, 1);
    queue[0] := Point.Create(startX, startY);
    visited[startX, startY] := true;
    count := 1;

    while Length(queue) > 0 do
    begin
      p := queue[0];
      for i := 1 to High(queue) do
        queue[i - 1] := queue[i];
      SetLength(queue, Length(queue) - 1);

      for i := 0 to 3 do
      begin
        var newX := p.X + directions[i].X;
        var newY := p.Y + directions[i].Y;
        if IsValidMove(newX, newY) and not visited[newX, newY] then
        begin
          visited[newX, newY] := true;
          Inc(count);
          SetLength(queue, Length(queue) + 1);
          queue[High(queue)] := Point.Create(newX, newY);
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

  // Копирование поля для ботов
  for botIndex := 0 to MAXIMUM_BOTS - 1 do
    for rowIndex := 0 to FIELD_WIDTH - 1 do
      for colIndex := 0 to FIELD_HEIGHT - 1 do
        botFields[botIndex, rowIndex, colIndex] := tempField[rowIndex, colIndex];

  // Размещение ботов
  var position := FindEmptyPosition(0);
  if (position.X < 0) or (position.Y < 0) then
    position := Point.Create(FIELD_WIDTH div 2, FIELD_HEIGHT div 2);
  for botIndex := 0 to MAXIMUM_BOTS - 1 do
  begin
    botFields[botIndex, position.X, position.Y] := BotCell;
    bots[botIndex].x := position.X;
    bots[botIndex].y := position.Y;
    bots[botIndex].active := true;
    position := FindEmptyPosition(botIndex); // Новая позиция для следующего бота
  end;

  // Размещение яблок и яда
  for botIndex := 0 to MAXIMUM_BOTS - 1 do
  begin
    for rowIndex := 0 to currentAppleCount - 1 do
    begin
      position := FindEmptyPosition(botIndex);
      if (position.X >= 0) and (position.Y >= 0) then
        botFields[botIndex, position.X, position.Y] := Apple;
    end;
    for rowIndex := 0 to 9 do
    begin
      position := FindEmptyPosition(botIndex);
      if (position.X >= 0) and (position.Y >= 0) then
        botFields[botIndex, position.X, position.Y] := Poison;
    end;
  end;
end;

procedure RenderGraph(data: array of real; xLeft, yTop, width, height: integer);
var
  index: integer;
  graphXPoints, graphYPoints: array of real;
  avgGraphXPoints, avgGraphYPoints: array of real;
  minFitness, maxFitness, minDuration, maxDuration, scaleX, scaleY: real;
  averageFitness: real;
begin
  ClearWindow(emptyCellColor);
  if Length(data) = 0 then exit;
  
  minFitness := 0;
  minDuration := MinimumValue(data);
  maxFitness := MaximumValue(data);
  maxDuration := maxFitness;
  averageFitness := 0;
  for index := 0 to Length(data) - 1 do
    averageFitness += data[index];
  if Length(data) > 0 then
    averageFitness /= Length(data);
  
  SetLength(graphXPoints, Length(data));
  SetLength(graphYPoints, Length(data));
  if Length(data) > 1 then
    scaleX := width / (Length(data) - 1)
  else
    scaleX := 0;
  if maxFitness = minFitness then
    scaleY := 0
  else
    scaleY := height / (maxFitness - minFitness);
  

  for index := 0 to Length(data) - 1 do
  begin
    graphXPoints[index] := xLeft + index * scaleX;
    if scaleY = 0 then
      graphYPoints[index] := yTop + height / 2
    else
      graphYPoints[index] := yTop + height - (data[index] - minFitness) * scaleY;
  end;
  
  Pen.Color := clYellow;
  Pen.Width := 1;
  if Length(data) > 1 then
  begin
    MoveTo(Round(graphXPoints[0]), Round(graphYPoints[0]));
    for index := 1 to Length(data) - 1 do
      LineTo(Round(graphXPoints[index]), Round(graphYPoints[index]));
  end;
  
  Brush.Color := clWhite;
  Pen.Color := clBlack;
  Pen.Width := 1;
  for index := 0 to Length(data) - 1 do
    FillCircle(Round(graphXPoints[index]), Round(graphYPoints[index]), 2);
  
  Pen.Color := clLightGray;
  Pen.Width := 1;
  for index := 1 to 4 do
  begin
    Line(xLeft, Round(yTop + index * height / 5), xLeft + width, Round(yTop + index * height / 5));
    Line(Round(xLeft + index * width / 5), yTop, Round(xLeft + index * width / 5), yTop + height);
  end;
  
  if Length(averageFitnessHistory) > 1 then
  begin
    SetLength(avgGraphXPoints, Length(averageFitnessHistory));
    SetLength(avgGraphYPoints, Length(averageFitnessHistory));
    for index := 0 to Length(averageFitnessHistory) - 1 do
    begin
      avgGraphXPoints[index] := xLeft + index * (width / (Length(averageFitnessHistory) - 1));
      if scaleY = 0 then
        avgGraphYPoints[index] := yTop + height / 2
      else
        avgGraphYPoints[index] := yTop + height - (averageFitnessHistory[index] - minFitness) * scaleY;
    end;
    
    Pen.Color := clCyan;
    Pen.Width := 1;
    MoveTo(Round(avgGraphXPoints[0]), Round(avgGraphYPoints[0]));
    for index := 1 to Length(averageFitnessHistory) - 1 do
      LineTo(Round(avgGraphXPoints[index]), Round(avgGraphYPoints[index]));
  end;
  
  var graphInfo := 'MaxFitness = ' + maxDuration.ToString + newline +
                   'MinFitness = ' + minDuration.ToString + newline +
                   'AvgFitness = ' + Round(averageFitness).ToString;
  DrawRectangledText(WINDOW_WIDTH div 2 - 100, WINDOW_HEIGHT - 100, 200, 80, graphInfo);
  Redraw;
end;

procedure Update;
var
  rowIndex: integer;
begin
  for var botIndex := 0 to MAXIMUM_BOTS - 1 do
  begin
    var appleCount := 0;
    for rowIndex := 0 to FIELD_WIDTH - 1 do
      for var colIndex := 0 to FIELD_HEIGHT - 1 do
        if botFields[botIndex, rowIndex, colIndex] = Apple then
          Inc(appleCount);
    if appleCount < MINIMUM_APPLES then
    begin
      var position := FindEmptyPosition(botIndex);
      if (position.X >= 0) and (position.Y >= 0) then
        botFields[botIndex, position.X, position.Y] := Apple;
    end;
  end;

  for var botIndex := 0 to MAXIMUM_BOTS - 1 do
    for rowIndex := 0 to FIELD_WIDTH - 1 do
      for var colIndex := 0 to FIELD_HEIGHT - 1 do
        if botFields[botIndex, rowIndex, colIndex] = Apple then
          if Random < APPLE_DECAY_PROBABILITY then
            botFields[botIndex, rowIndex, colIndex] := Poison;
  
  rowIndex := 0;
  while rowIndex < MAXIMUM_BOTS do
  begin
    if bots[rowIndex].active then
    begin
      var remainingCommands := maximumThinkTime - 1;
      while (remainingCommands > 0) and (bots[rowIndex].genome[bots[rowIndex].genomePosition] <> 0) do
      begin
        ExecuteCommand(rowIndex, bots[rowIndex]);
        remainingCommands -= 1;
      end;
      ExecuteCommand(rowIndex, bots[rowIndex]);
      
      if bots[rowIndex].actionCount >= MAXIMUM_ACTIONS then
      begin
        bots[rowIndex].active := false;
        botFields[rowIndex, bots[rowIndex].x, bots[rowIndex].y] := Empty;
        Dec(activeBotCount);
      end;
      
      if activeBotCount <= 0 then
      begin
        CreateNewPopulation;
        ResetField;
        activeBotCount := MAXIMUM_BOTS;
        Inc(generationNumber);
        AddGenerationDuration(Milliseconds - generationStartTime);
        generationStartTime := Milliseconds;
        if generationNumber > skipRenderGenerations then
          if not isSimulationRendered then
            RenderGraph(generationDurations, 0, 0, WINDOW_WIDTH, WINDOW_HEIGHT);
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
  if AnyKeyPressed then
  begin
    while AnyKeyPressed do;
    isSimulationRendered := not isSimulationRendered;
  end;
  if MousePressed then
  begin
    while MousePressed do;
    isSimulationPaused := not isSimulationPaused;
  end;
end;

begin
  Initialize;
  while true do
  begin
    HandleInput;
    if not isSimulationPaused then
      Update;
    if generationNumber > skipRenderGenerations then
      if isSimulationRendered then
        Render;
    UpdateStatus;
  end;
end.

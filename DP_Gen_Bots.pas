{
  Генетические боты: популяция ботов с геномом из 64 команд эволюционирует
  на клеточном поле со стенами, яблоками и ядом.

  Раскладку каждого поколения см. в DP_World, виртуальную машину генома —
  в DP_Bot, отбор и адаптацию параметров — в DP_Evolution.

  Управление:
    пробел          пауза
    G / F           график по поколениям / поле выбранного бота
    стрелки         выбрать бота, B — самый приспособленный
    щелчок мышью    переключить график и поле

  Каждое поколение дописывается строкой в gen_bots_log.csv.
}
uses GraphABC, DP_Config, DP_World, DP_Bot, DP_Evolution, DP_Render, DP_Control;

type
  ViewModeType = (ViewField, ViewGraph);

var
  viewMode: ViewModeType := ViewGraph;
  isSimulationPaused: boolean := False;
  ///Состояние кнопки мыши на прошлом кадре — для детекции фронта нажатия
  wasMousePressed: boolean := False;

procedure HandleInput;
begin
  // Реакция на фронт нажатия. Прежняя версия крутила пустой цикл, пока
  // клавиша удерживается: это жгло ядро и блокировало симуляцию.
  if IsKeyPressed(VK_Space) then
    isSimulationPaused := not isSimulationPaused;
  if IsKeyPressed(VK_G) then
    viewMode := ViewGraph;
  if IsKeyPressed(VK_F) then
    viewMode := ViewField;
  if IsKeyPressed(VK_B) then
  begin
    SelectBestBot;
    viewMode := ViewField;
  end;
  if IsKeyPressed(VK_Left) then
  begin
    SelectBot(-1);
    viewMode := ViewField;
  end;
  if IsKeyPressed(VK_Right) then
  begin
    SelectBot(1);
    viewMode := ViewField;
  end;

  if MousePressed and not wasMousePressed then
    if viewMode = ViewField then
      viewMode := ViewGraph
    else
      viewMode := ViewField;
  wasMousePressed := MousePressed;
end;

begin
  SetupWindow;
  ShowStartupMessage;
  InitializeEvolution;
  UpdateStatus;

  while true do
  begin
    HandleInput;

    if isSimulationPaused then
      // В паузе считать нечего — отдаём процессор системе вместо
      // прокрутки пустого цикла на полной скорости.
      Sleep(16)
    else if SimulationStep then
    begin
      // Заголовок окна и график обновляются раз в поколение, а не каждый
      // кадр: SetWindowTitle маршалит вызов в поток окна и стоит дорого.
      UpdateStatus;
      if viewMode = ViewGraph then
        RenderGraphView(12, 12, WINDOW_WIDTH - 24, WINDOW_HEIGHT - 110);
    end;

    if viewMode = ViewField then
      RenderFieldView;
  end;
end.

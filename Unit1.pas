unit Unit1;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, Dialogs, ExtDlgs, ExtCtrls,
  StdCtrls, LCLIntf, LCLType, Math;

type

  { TForm1 }

  TForm1 = class(TForm)
    ButtonLoad: TButton;
    ButtonAffine: TButton;
    ButtonSaveAffine: TButton;
    ButtonInverse: TButton;
    ButtonSaveInverse: TButton;
    ButtonNonlinear: TButton;
    ButtonSaveNonlinear: TButton;
    EditAngle: TEdit;
    EditScale: TEdit;
    Label1: TLabel;
    Label2: TLabel;
    Image1: TImage;
    Image2: TImage;
    Image3: TImage;
    Image4: TImage;
    OpenPictureDialog1: TOpenPictureDialog;
    SavePictureDialog1: TSavePictureDialog;
    procedure ButtonLoadClick(Sender: TObject);
    procedure ButtonAffineClick(Sender: TObject);
    procedure ButtonSaveAffineClick(Sender: TObject);
    procedure ButtonInverseClick(Sender: TObject);
    procedure ButtonSaveInverseClick(Sender: TObject);
    procedure ButtonNonlinearClick(Sender: TObject);
    procedure ButtonSaveNonlinearClick(Sender: TObject);
  private
  public
  end;

var
  Form1: TForm1;

implementation

{$R *.lfm}

{ TForm1 }

function ConvertTo24Bit(aValue: TBitmap): TBitmap;
begin
  Result := TBitmap.Create;
  if aValue.PixelFormat <> pf24bit then
  begin
    Result.PixelFormat := pf24bit;
    Result.SetSize(aValue.Width, aValue.Height);
    Result.Canvas.Draw(0, 0, aValue);
  end
  else
    Result.Assign(aValue);
end;

procedure ReadAngleScale(var phi, k: real);
var
  fs: TFormatSettings;
begin
  fs := DefaultFormatSettings;
  fs.DecimalSeparator := '.';
  if not TryStrToFloat(Trim(Form1.EditAngle.Text), phi, fs) then
    phi := 0;
  phi := phi * pi / 180; // градусы -> радианы
  if not TryStrToFloat(Trim(Form1.EditScale.Text), k, fs) then
    k := 1;
  if k = 0 then
    k := 1;
end;

// ---------------------------------------------------------------------
// Функция нелинейного преобразования (Вариант 1): i = x'^3/(1+x'^2)
// и её производная - для обратного (численного) решения методом Ньютона.
// ---------------------------------------------------------------------
function NonlinearF(x: real): real;
begin
  Result := x * x * x / (1 + x * x);
end;

function NonlinearFPrime(x: real): real;
begin
  Result := sqr(x) * (3 + sqr(x)) / sqr(1 + sqr(x));
end;

// находим x' такое, что NonlinearF(x') = targetI, методом Ньютона
// (функция монотонна на всей числовой прямой, поэтому решение единственно)
function InverseNonlinearF(targetI: real): real;
var
  x, fx, fpx: real;
  n: Integer;
begin
  x := targetI; // хорошее начальное приближение, т.к. f(x)~x при больших |x|
  for n := 1 to 30 do
  begin
    fx := NonlinearF(x) - targetI;
    fpx := NonlinearFPrime(x);
    if Abs(fpx) < 1e-9 then
      Break;
    if Abs(fx) < 1e-6 then
      Break;
    x := x - fx / fpx;
  end;
  Result := x;
end;

// ---------------------------------------------------------------------
// Загрузка исходного изображения
// ---------------------------------------------------------------------
procedure TForm1.ButtonLoadClick(Sender: TObject);
var
  tmp: TBitmap;
begin
  if OpenPictureDialog1.Execute then
  begin
    Image1.Picture.LoadFromFile(OpenPictureDialog1.FileName);
    if Image1.Picture.Bitmap.PixelFormat <> pf24bit then
    begin
      tmp := ConvertTo24Bit(Image1.Picture.Bitmap);
      Image1.Picture.Bitmap.Assign(tmp);
      tmp.Free;
    end;
    Image1.Stretch := True;
    Image1.Proportional := True;
  end;
end;

// ---------------------------------------------------------------------
// Прямое аффинное преобразование: масштабирование (k) + поворот (phi)
// относительно центра изображения. Реализовано как обратное отображение
// (для каждого пикселя результата ищем пиксель источника), чтобы не
// было пропусков.
// ---------------------------------------------------------------------
procedure TForm1.ButtonAffineClick(Sender: TObject);
var
  i, j, i1, j1, w, h: Integer;
  phi, k: real;
begin
  if Image1.Picture.Graphic = nil then
  begin
    ShowMessage('Сначала загрузите изображение!');
    Exit;
  end;

  ReadAngleScale(phi, k);
  w := Image1.Picture.Bitmap.Width;
  h := Image1.Picture.Bitmap.Height;

  Image2.Picture.Bitmap.PixelFormat := pf24bit;
  Image2.Picture.Bitmap.SetSize(w, h);
  Image2.Picture.Bitmap.Canvas.Brush.Color := RGB(255, 255, 255);
  Image2.Picture.Bitmap.Canvas.FillRect(Rect(0, 0, w, h));

  for i := 0 to w - 1 do
    for j := 0 to h - 1 do
    begin
      i1 := round(((i - w div 2) * cos(phi) - (j - h div 2) * sin(phi)) / k + w div 2);
      j1 := round(((i - w div 2) * sin(phi) + (j - h div 2) * cos(phi)) / k + h div 2);
      if (i1 >= 0) and (j1 >= 0) and (i1 < w) and (j1 < h) then
        Image2.Picture.Bitmap.Canvas.Pixels[i, j] :=
          Image1.Picture.Bitmap.Canvas.Pixels[i1, j1];
    end;

  Image2.Stretch := True;
  Image2.Proportional := True;
  Image2.Invalidate;
end;

procedure TForm1.ButtonSaveAffineClick(Sender: TObject);
begin
  if SavePictureDialog1.Execute then
    Image2.Picture.SaveToFile(SavePictureDialog1.FileName);
end;

// ---------------------------------------------------------------------
// Обратное аффинное преобразование: восстанавливаем исходное изображение
// из результата прямого преобразования (Image2 -> Image3).
// ---------------------------------------------------------------------
procedure TForm1.ButtonInverseClick(Sender: TObject);
var
  i, j, i1, j1, w, h: Integer;
  phi, k: real;
begin
  if Image2.Picture.Graphic = nil then
  begin
    ShowMessage('Сначала выполните прямое преобразование!');
    Exit;
  end;

  ReadAngleScale(phi, k);
  w := Image2.Picture.Bitmap.Width;
  h := Image2.Picture.Bitmap.Height;

  Image3.Picture.Bitmap.PixelFormat := pf24bit;
  Image3.Picture.Bitmap.SetSize(w, h);
  Image3.Picture.Bitmap.Canvas.Brush.Color := RGB(255, 255, 255);
  Image3.Picture.Bitmap.Canvas.FillRect(Rect(0, 0, w, h));

  for i := 0 to w - 1 do
    for j := 0 to h - 1 do
    begin
      i1 := round(((i - w div 2) * cos(-phi) - (j - h div 2) * sin(-phi)) * k + w div 2);
      j1 := round(((i - w div 2) * sin(-phi) + (j - h div 2) * cos(-phi)) * k + h div 2);
      if (i1 >= 0) and (j1 >= 0) and (i1 < w) and (j1 < h) then
        Image3.Picture.Bitmap.Canvas.Pixels[i, j] :=
          Image2.Picture.Bitmap.Canvas.Pixels[i1, j1];
    end;

  Image3.Stretch := True;
  Image3.Proportional := True;
  Image3.Invalidate;
end;

procedure TForm1.ButtonSaveInverseClick(Sender: TObject);
begin
  if SavePictureDialog1.Execute then
    Image3.Picture.SaveToFile(SavePictureDialog1.FileName);
end;

// ---------------------------------------------------------------------
// Функциональное (нелинейное) преобразование, Вариант 1:
// i = x'^3/(1+x'^2), j = y'.
// Для каждого пикселя результата (i,j) обратной функцией находим x',
// координату j'=j не меняем.
// ---------------------------------------------------------------------
procedure TForm1.ButtonNonlinearClick(Sender: TObject);
var
  i, j, i1, j1, w, h: Integer;
  x1: real;
begin
  if Image1.Picture.Graphic = nil then
  begin
    ShowMessage('Сначала загрузите изображение!');
    Exit;
  end;

  w := Image1.Picture.Bitmap.Width;
  h := Image1.Picture.Bitmap.Height;

  Image4.Picture.Bitmap.PixelFormat := pf24bit;
  Image4.Picture.Bitmap.SetSize(w, h);
  Image4.Picture.Bitmap.Canvas.Brush.Color := RGB(255, 255, 255);
  Image4.Picture.Bitmap.Canvas.FillRect(Rect(0, 0, w, h));

  for i := 0 to w - 1 do
    for j := 0 to h - 1 do
    begin
      x1 := InverseNonlinearF(i);
      i1 := round(x1);
      j1 := j;
      if (i1 >= 0) and (j1 >= 0) and (i1 < w) and (j1 < h) then
        Image4.Picture.Bitmap.Canvas.Pixels[i, j] :=
          Image1.Picture.Bitmap.Canvas.Pixels[i1, j1];
    end;

  Image4.Stretch := True;
  Image4.Proportional := True;
  Image4.Invalidate;
end;

procedure TForm1.ButtonSaveNonlinearClick(Sender: TObject);
begin
  if SavePictureDialog1.Execute then
    Image4.Picture.SaveToFile(SavePictureDialog1.FileName);
end;

end.

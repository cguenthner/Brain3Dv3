% Check MATLAB version
if verLessThan('matlab','8.0.0.783')
    str = '';
    while ~(strcmp(str,'y') || strcmp(str,'n'))
        str = input(['It''s recommended that you only run this software on MATLAB 2012b or later. You''re currently running MATLAB ' version('-release') '. Do you want to continue with installation? (y/n)'],'s');
    end
    if strcmp(str,'n')
        return
    end
end

% Check that necessary toolboxes are installed
v = ver;
[installedToolboxes{1:length(v)}] = deal(v.Name);
tf = ismember({'Image Processing Toolbox','Statistics Toolbox'},installedToolboxes);
if isequal(tf,[0 1])
    disp('The Image Processing Toolbox must be installed to run this software. Install failed.');
    return
elseif isequal(tf,[1 0])
    disp('The Statistics Toolbox must be installed to run this software. Install failed.');
    return
elseif isequal(tf,[0 0])
    disp('The Statistics and Image Processing Toolboxes must be installed to run this software. Install failed.');
    return
end

try
    % Determine image processing toolbox path
    ImagePath = [matlabroot '\toolbox\images\images\'];
    % Copy imregisterB to the image processing toolbox subfolder
    copyfile('imregisterB_tocopy',[ImagePath 'imregisterB.m']);
    % Have to remove image processing toolbox path from Matlab path and then
    % add it back again in order to get imregisterB in the path
    rmpath(ImagePath);
    addpath(genpath(ImagePath),'-frozen');
catch
    disp('Failed to install imregisterB. Install failed.');
    return
end

% Determine string to add to startup.m file
try
    CurrDir = which('install3DBrain');
    [CurrDir,~,~] = fileparts(CurrDir);
    addstr = ['try addpath(genpath(''' CurrDir ''')); end'];

    startm = userpath;
    startm = [startm(1:end-1) '\startup.m'];
    f = fopen(startm,'a+');
    frewind(f);
    if isempty(strfind([fread(f,'*char')]',addstr))
        fprintf(f,'%s',addstr);
    end
    fclose(f);
catch
    disp('Failed to add Brain3D path to startup.m. You will have to manually add the Brain3D folder to the MATLAB path.');
end

str = '';
while ~(strcmp(str,'y') || strcmp(str,'n'))
    str = input(['You must restart MATLAB. Would you like to do this now? (y/n)'],'s');
    if strcmp(str,'n')
        return
    elseif strcmp(str,'y')
        !matlab &
        exit
    end
end

    
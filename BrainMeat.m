function [ hWindow ] = BrainMeat( fn )

    WindowSize = get(0,'ScreenSize');
    WindowSize = round([1/8*WindowSize(3) 1/16*WindowSize(4) 6/8*WindowSize(3) 14/16*WindowSize(4)]);
    hStagePanel = -1;
    CurrSlide = 1;
    CurrSlice = 1;
    gray = permute([linspace(0,1,256); linspace(0,1,256); linspace(0,1,256)],[2 1]);
    
    % Setup default registration parameters
    SiftParams.alpha=2;
    SiftParams.d=20;
    SiftParams.gamma=0.15;
    SiftParams.nlevels=4;
    SiftParams.wsize=5;
    SiftParams.topwsize=20;
    SiftParams.nIterations=60;
    SiftParams.gridspacing = 1;
    SiftParams.patchsize = 8;
    SiftParamsDefault = SiftParams;
    [RigidOptimizer, RigidMetric] = imregconfig('multimodal');
    
    if ischar(fn)
        % A filename was passed - must load existing file
        msg = waitbar(0,'Loading data file...');
        dat = load(fn);
        brain = dat.brain;
        ss = dat.ss;
        
        % Check if image files can be found
        FilesMissing = 1;
        while FilesMissing
            FileList = [];
            for i = 1:brain.FileNum
                if ~exist(brain.FullNames{i},'file')
                    [~,FileList{end+1},ext] = fileparts(brain.FullNames{i});
                    FileList{end} = [FileList{end} ext];
                end
            end
            if isempty(FileList)
                FilesMissing = 0;
            else
                if length(FileList)>10
                    ans = questdlg(['The following files are associated with this project but could not be found:' {FileList{1:5} '.' '.' '.' FileList{end-4:end}} 'All files belonging to this project must be in the same folder. Would you like to locate them?']);
                else
                    ans = questdlg(['The following files are associated with this project but could not be found:' FileList 'All files belonging to this project must be in the same folder. Would you like to locate them?']);
                end
                if strcmp(ans,'Yes')
                    % Locate missing files
                    newdir = uigetdir;
                    for i = 1:brain.FileNum
                        [~,filename,ext] = fileparts(brain.FullNames{i});
                        filename = [filename ext];
                        brain.FullNames{i} = [newdir '\' filename];
                    end
                    for j = 1:brain.GroupNum
                        for k = 1:size(brain.FileGroups,2)
                            if ~isempty(brain.FileGroups{j,k})
                                [~,filename,~] = fileparts(brain.FileGroups{j,k});
                                filename = [filename ext];
                                brain.FileGroups{j,k} = [newdir '\' filename];
                            end
                        end
                    end
                else
                    delete(msg);
                    return;
                end
            end
         end
            
                    
        delete(msg);
    else
        % This is a new file
        dat = struct;
        dat.stage = 1;
        dat.AvailableStages = [1 0 0 0 0 0];
        brain = -1;
        ss = -1;
    end
    
    % Create figure
    hWindow = figure('OuterPosition',WindowSize,...
        'Name','3D Brain',...
        'NumberTitle','off',...
        'Toolbar','none',...
        'MenuBar','none',...
        'Resize','on',...
        'Color',[0.9412 0.9412 0.9412],...
        'CloseRequestFcn',{@CloseWindow});
    
    % Menus
    hFileMenu = uimenu(hWindow,'Label','File');
    hSettingsMenu = uimenu(hWindow,'Label','Settings');
    hHelpMenu = uimenu(hWindow,'Label','Help');
    hSave = uimenu(hFileMenu,'Label','Save','Callback',@SaveBrain);
    hSaveAs = uimenu(hFileMenu,'Label','Save as...','Callback',@SaveBrain);
    uimenu(hSettingsMenu,'Label','Rigid...','Callback',@RigidSettings);
    uimenu(hSettingsMenu,'Label','Non-rigid...','Callback',@NonrigidSettings);
    uimenu(hHelpMenu,'Label','Help...','Callback',@HelpBrain);
    uimenu(hHelpMenu,'Label','About...','Callback',@AboutBrain);
    
    function AboutBrain(source,eventdata)
        WindowPos = getpixelposition(hWindow);
        WindowPos = [WindowPos(1)+WindowPos(3)/2-250 WindowPos(2)+WindowPos(4)/2-250 500 500];
        hAbout = figure('Position',WindowPos,'Name','About','NumberTitle','off','Toolbar','none','MenuBar','none','Resize','off','Color',[0.9412 0.9412 0.9412],'WindowStyle','modal');
        AboutText = {'Developed by Casey Guenthner in Liqun Luo''s lab at the Howard Hughes Medical Institute and Department of Biology at Stanford University in California. Jing Xiong developed use of SIFT flow for slice alignment. Use of the following packages in this software is gratefully acknowledged:';
                     'xml2struct by  Wouter Falkena';
                     'SIFT flow by Ce Liu, Jenny Yuen, Antonio Torralba, Josef Sivic, and William T. Freeman'};
        urls = {'http://www.stanford.edu/group/luolab/';
                'http://www.mathworks.com/matlabcentral/fileexchange/28518-xml2struct';
                'http://people.csail.mit.edu/celiu/ECCV2008/'};
        yshift=50;
        for i = 1:length(AboutText);
            hText(i) = uicontrol('Parent',hAbout,'Style','text','HorizontalAlignment','Left','Units','Pixels','Position',[50 50 WindowPos(3)-100 WindowPos(4)-50],'FontSize',13,'ButtonDownFcn',@(source,eventdata) web(urls{i},'-browser'),'Enable','inactive');
            [wrapped,pos] = textwrap(hText(i),AboutText(i));
            yshift = yshift+pos(4);
            pos(2) = WindowPos(4)-yshift-(i-1)*30;
            set(hText(i),'String',wrapped,'Position',pos);
        end
    end
    
    function HelpBrain(source,eventdata)
        [path,~,~] = fileparts(mfilename('fullpath'));
        path = [path '\help\help.html'];
        web(path,'-browser');
    end

    function RigidSettings(source,eventdata)
        WindowPos = getpixelposition(hWindow);
        WindowPos = [WindowPos(1)+WindowPos(3)/2-250 WindowPos(2)+WindowPos(4)/2-250 410 420];
        hRigidSettings = figure('Position',WindowPos,'Name','Rigid Settings','NumberTitle','off','Toolbar','none','MenuBar','none','Resize','off','Color',[0.9412 0.9412 0.9412],'WindowStyle','modal');
        uicontrol('Style','text','Parent',hRigidSettings,'String','Rigid Registration Parameters','Position',[0 390 410 20]);
        
        % Optimizer settings
        ooptions = {'OnePlusOneEvolutionary','RegularStepGradientDescent'};
        opanel = uipanel('Parent',hRigidSettings,'Units','pixels','Position',[0 190 400 200],'BorderType','none');       %,'BackgroundColor','red');
        uicontrol('Style','text','Parent',opanel,'String','Optimizer','HorizontalAlignment','right','Position',[0 167.5 190 20]);
        oselect = uicontrol('Style','popupmenu','Parent',opanel,'String',ooptions,'Position',[200 170 200 20],'Callback',{@OChange});
        if isa(RigidOptimizer,'registration.optimizer.OnePlusOneEvolutionary')
            set(oselect,'Value',1)
        else
            set(oselect,'Value',2);
        end
        otext = [];
        ofields = [];
        OChange;
        
        % Metric settings
        moptions = {'MattesMutualInformation','MeanSquares'};
        mpanel = uipanel('Parent',hRigidSettings,'Units','pixels','Position',[0 60 400 130],'BorderType','none');            % 'BackgroundColor','red');
        uicontrol('Style','text','Parent',mpanel,'String','Metric','HorizontalAlignment','right','Position',[0 97.5 190 20]);
        mselect = uicontrol('Style','popupmenu','Parent',mpanel,'String',moptions,'Position',[200 100 200 20],'Callback',{@MChange});
        if isa(RigidMetric,'registration.metric.MattesMutualInformation')
            set(mselect,'Value',1)
        else
            set(mselect,'Value',2);
        end
        mtext = [];
        mfields = [];
        MChange;
        
        % Push buttons
        uicontrol('Parent', hRigidSettings,'Style','pushbutton','String','OK','Position',[10 10 195 50],'Callback',{@RigidOK});
        uicontrol('Parent', hRigidSettings,'Style','pushbutton','String','Restore Defaults','Position',[205 10 195 50],'Callback',{@RigidDefault});
 
        function RigidOK(source,eventdata) 
            try
                for i = 1:length(mfields)
                    RigidMetric.(get(mtext(i),'String')) = str2num(get(mfields(i),'String'));
                end
                for i = 1:length(ofields)
                    RigidOptimizer.(get(otext(i),'String')) = str2num(get(ofields(i),'String'));
                end
                close(hRigidSettings);
            catch err
                msgbox(['The following error message was returned when setting registration parameters:' getReport(err,'extended','hyperlinks','off')],'Error','error');
            end
        end
        
        function RigidDefault(source,eventdata)
            [RigidOptimizer, RigidMetric] = imregconfig('multimodal');
            set(oselect,'Value',1);
            set(mselect,'Value',1);
            MChange;
            OChange;
        end
        
        function OChange(varargin)
            delete([otext ofields]);
            otext = [];
            ofields = [];
            if ~strcmp(class(RigidOptimizer),['registration.optimizer.' ooptions{get(oselect,'Value')}])
                RigidOptimizer = registration.optimizer.(ooptions{get(oselect,'Value')});
            end
            oprops = properties(RigidOptimizer);
            for i = 1:length(oprops)
                otext(i) = uicontrol('Style','text','Parent',opanel,'String',oprops{i},'HorizontalAlignment','right','Position',[0 170-i*30 190 20]);
                ofields(i) = uicontrol('Style','edit','Parent',opanel,'String',num2str(RigidOptimizer.(oprops{i})),'BackgroundColor','white','Position',[200 167.5-i*30 60 25]);
            end      
        end
        
        function MChange(varargin)
            delete([mtext mfields]);
            mtext = [];
            mfields = [];
            if ~strcmp(class(RigidMetric),['registration.metric.' moptions{get(mselect,'Value')}])
                RigidMetric = registration.metric.(moptions{get(mselect,'Value')});
            end
            mprops = properties(RigidMetric);
            for i = 1:length(mprops)
                mtext(i) = uicontrol('Style','text','Parent',mpanel,'String',mprops{i},'HorizontalAlignment','right','Position',[0 100-i*30 190 20]);
                mfields(i) = uicontrol('Style','edit','Parent',mpanel,'String',num2str(RigidMetric.(mprops{i})),'BackgroundColor','white','Position',[200 97.5-i*30 60 25]);
            end      
        end
        
    end

    function NonrigidSettings(source,eventdata)
        WindowPos = getpixelposition(hWindow);
        WindowPos = [WindowPos(1)+WindowPos(3)/2-250 WindowPos(2)+WindowPos(4)/2-250 270 400];
        hNonrigidSettings = figure('Position',WindowPos,'Name','Non-rigid Settings','NumberTitle','off','Toolbar','none','MenuBar','none','Resize','off','Color',[0.9412 0.9412 0.9412],'WindowStyle','modal');
        uicontrol('Style','text','Parent',hNonrigidSettings,'String','SIFT Flow Parameters','Position',[0 350 270 20]);
        params = fieldnames(SiftParams);
        for i = 1:length(params)
            uicontrol('Style','text','Parent',hNonrigidSettings,'String',params{i},'HorizontalAlignment','left','Position',[50 350-i*30 75 20]);
            ParamFields(i) = uicontrol('Style','edit','Parent',hNonrigidSettings,'String',num2str(SiftParams.(params{i})),'BackgroundColor','white','Position',[150 347.5-i*30 60 25],'Callback',{@CheckSiftParams});
        end
        uicontrol('Parent', hNonrigidSettings,'Style','pushbutton','String','OK','Position',[10 10 120 50],'Callback',{@NonRigidOK});
        uicontrol('Parent', hNonrigidSettings,'Style','pushbutton','String','Restore Defaults','Position',[140 10 120 50],'Callback',{@NonRigidDefault});
        
        function CheckSiftParams(source,eventdata)
        	newval = str2num(get(source,'String'));
            if isempty(newval)
                set(source,'String',SiftParams.(params{find(source==ParamFields)}));
            end
        end
        
        function NonRigidOK(source,eventdata)
            for i = 1:length(params)
                SiftParams.(params{i}) = str2num(get(ParamFields(i),'String'));
            end
            close(hNonrigidSettings);
        end
        
        function NonRigidDefault(source,eventdata)
            SiftParams = SiftParamsDefault;
            for i = 1:length(params)
                set(ParamFields(i),'String',num2str(SiftParams.(params{i})));
            end
        end
    end


    % Navigation elements
    hControlPanel = uipanel('Parent',hWindow,'Units','normalized','Position',[0.65 0.02 0.34 0.96]);
    hStage(1) = uicontrol('Parent',hControlPanel,'Style','text', 'HorizontalAlignment','Left','Units','normalized','Position',[0.05 0.96 0.8 0.03],'FontUnits','normalized','FontSize',0.8,'ButtonDownFcn',{@StageChanged},'Enable','inactive','String','1. Import');
    hStage(2) = uicontrol('Parent',hControlPanel,'Style','text', 'HorizontalAlignment','Left','Units','normalized','Position',[0.05 0.93 0.8 0.03],'FontUnits','normalized','FontSize',0.8,'ButtonDownFcn',{@StageChanged},'Enable','inactive','String','2. Segment');
    hStage(3) = uicontrol('Parent',hControlPanel,'Style','text', 'HorizontalAlignment','Left','Units','normalized','Position',[0.05 0.90 0.8 0.03],'FontUnits','normalized','FontSize',0.8,'ButtonDownFcn',{@StageChanged},'Enable','inactive','String','3. Order');
    hStage(4) = uicontrol('Parent',hControlPanel,'Style','text', 'HorizontalAlignment','Left','Units','normalized','Position',[0.05 0.87 0.8 0.03],'FontUnits','normalized','FontSize',0.8,'ButtonDownFcn',{@StageChanged},'Enable','inactive','String','4. Pre-processing');
    hStage(5) = uicontrol('Parent',hControlPanel,'Style','text', 'HorizontalAlignment','Left','Units','normalized','Position',[0.05 0.84 0.8 0.03],'FontUnits','normalized','FontSize',0.8,'ButtonDownFcn',{@StageChanged},'Enable','inactive','String','5. Alignment');   
    hStage(6) = uicontrol('Parent',hControlPanel,'Style','text', 'HorizontalAlignment','Left','Units','normalized','Position',[0.05 0.81 0.8 0.03],'FontUnits','normalized','FontSize',0.8,'ButtonDownFcn',{@StageChanged},'Enable','inactive','String','6. Export');
    hPreviousStage = uicontrol('Parent',hControlPanel,'Style','pushbutton','String','Previous','Units','normalized','Position',[0.02 0.01 0.47 0.1],'FontUnits','normalized','FontSize',0.3,'Callback',{@StageChanged});
    hNextStage = uicontrol('Parent',hControlPanel,'Style','pushbutton','String','Next','Units','normalized','Position',[0.51 0.01 0.47 0.1],'FontUnits','normalized','FontSize',0.3,'Callback',{@StageChanged});
    %set(hStage(6),'Visible','off');
    SetStage;
    
    function SaveBrain(source,eventdata)
        if (source==hSave || source==-1) && ischar(fn)
            % Save file using previous filename
            fnout = fn;
        else
            % Get new file name from user
            [fnout,FilePath] = uiputfile({'*.mat' '3D Brain Project File'});
            if ischar(fnout) && ischar(FilePath)
                fnout = strcat(FilePath,fnout);
            else
                fnout = 0;
            end
            fn = fnout;
        end
        if ischar(fnout)
            hStat = statmsg('Saving file...');
            dat.brain = brain;
            dat.ss = ss;
            save(fnout,'-struct','dat');
            delete(hStat);
        end
    end
    
    %%
    function StageChanged(source, eventdata)
        PreviousStage = dat.stage;
        if source == hPreviousStage
            NewStage = PreviousStage-1;
            while NewStage>0 && ~dat.AvailableStages(NewStage) 
                NewStage = NewStage-1;
            end
            if NewStage ~= 0
                dat.stage = NewStage;
            end
        elseif source == hNextStage
            NewStage = PreviousStage+1;
            while NewStage<7 && ~dat.AvailableStages(NewStage)
                NewStage = NewStage+1;
            end
            if NewStage ~= 7
                dat.stage = NewStage;
            end
        elseif dat.AvailableStages(find(source==hStage))
            dat.stage = find(source==hStage);
        end
        if PreviousStage==2 && dat.stage>2 && isa(ss,'SliceSet') && ss.SliceNum < 2
            msgbox('You must have at least two slices segmented to continue.','Error','error');
            dat.stage = 2;
        elseif PreviousStage ~= dat.stage
            set(hStage(PreviousStage),'ForegroundColor','black');
            SetStage;
        end
    end
    
    %%
    function UpdateStageList()
        
        % Set GUI elements to appropriate state for this stage
        set(hStage(dat.stage),'ForegroundColor','red');
        for i=1:6
            if dat.AvailableStages(i)
                set(hStage(i),'Enable','inactive');
            else
                set(hStage(i),'Enable','off');
            end
        end
        if dat.stage==1
            set(hPreviousStage,'Enable','off');
        elseif dat.stage == 6
            set(hNextStage,'Enable','off');
        end
        if sum(dat.AvailableStages(dat.stage+1:end))==0
            set(hNextStage,'Enable','off');
        else
            set(hNextStage,'Enable','on');
        end
        if sum(dat.AvailableStages(1:dat.stage-1))==0
            set(hPreviousStage,'Enable','off');
        else
            set(hPreviousStage,'Enable','on');
        end
        
    end

    function SetStage()
        
        UpdateStageList;
        
        % Delete previous stage GUI elements
        for i = 1:length(hStagePanel)
            if ishandle(hStagePanel(i))
                delete(hStagePanel(i));
            end
        end
        
        % Each function returns uipanel handle containing all the GUI
        % elements for that stage so that they can be deleted when the
        % stage changes
        switch dat.stage
            case 1
                [hStagePanel] = BrainImport(hWindow,hStage,hNextStage,hPreviousStage);
            case 2
                [hStagePanel] = BrainSegment(hWindow,hStage,hNextStage,hPreviousStage);
            case 3
                [hStagePanel] = BrainOrder(hWindow,hStage,hNextStage,hPreviousStage);
            case 4
                [hStagePanel] = BrainPreprocess(hWindow,hStage,hNextStage,hPreviousStage);
            case 5
                [hStagePanel] = BrainAlign(hWindow,hStage,hNextStage,hPreviousStage);
            case 6
                [hStagePanel] = BrainExport(hWindow,hStage,hNextStage,hPreviousStage);
        end
    end
    
    %%
    function CloseWindow(source, eventdata)
        shouldsave = questdlg('Would you like to save this project file?');
        if strcmp(shouldsave,'Yes')
            SaveBrain(-1,-1);
            delete(hWindow);
        elseif strcmp(shouldsave,'No')
            delete(hWindow);  
        end
    end

    %%
    
    function [hStagePanel] = BrainImport(hWindow,hStage,hNextStage,hPreviousStage)
        hMainPanel = uipanel('Parent',hWindow,'Units','normalized','Position',[0.015 0.02 0.62 0.96]);
        hStageControl = uipanel('Parent',hWindow,'Units','normalized','Clipping','off','Position',[0.655 0.14 0.33 0.62]);
        hStagePanel = [hMainPanel hStageControl];
        
        % Create radio button group for image type
        hFilesContain = uibuttongroup('Parent',hStageControl,'Units','normalized','Position',[0.02 0.8 0.96 0.2],'Title','Files Contain','SelectionChangeFcn',{@ChangeImportMode});
        hSlideRadio = uicontrol('Style','radiobutton','Parent',hFilesContain,'Units','normalized','Position',[0.05 0.7 0.9 0.2],'String','Whole slides');
        hStackRadio = uicontrol('Style','radiobutton','Parent',hFilesContain,'Units','normalized','Position',[0.05 0.4 0.9 0.2],'String','Slice stacks');
        hSliceRadio = uicontrol('Style','radiobutton','Parent',hFilesContain,'Units','normalized','Position',[0.05 0.1 0.9 0.2],'String','Single slices');
 
        % File selection elements
        hAddFiles = uicontrol('Parent',hStageControl,'Style','pushbutton','String','Select File(s)','Units','normalized','Position',[0.02 0.7 0.4 0.08],'FontUnits','normalized','FontSize',0.5,'Enable','off','Callback',{@AddFiles});
        hFileTable = uitable('Parent',hMainPanel,'ColumnName',{'File','Available Channels','Import Channel'}, 'RowName',[],'ColumnEditable',[false false true],'Units','normalized','Position',[0.02 0.51 0.96 0.47],'CellEditCallback',{@ChannelSelected},'CellSelectionCallback',{@RowSelected});
        set(hFileTable,'Units','pixels');
        TablePos = get(hFileTable,'Position');
        set(hFileTable,'Units','normalized');
        set(hFileTable,'ColumnWidth',{TablePos(3)*0.4 TablePos(3)*0.4 TablePos(3)*0.2});
        
        % Delimiter elements
        uicontrol('Style','text','Parent',hStageControl,'String','Channel Delimiter','Units','normalized','HorizontalAlignment','left','Position',[0.44 0.74 0.25 0.04]);
        uicontrol('Style','text','Parent',hStageControl,'String','Slice Delimiter','Units','normalized','HorizontalAlignment','left','Position',[0.44 0.69 0.25 0.04]);
        uicontrol('Style','text','Parent',hStageControl,'String','Downsample','Units','normalized','HorizontalAlignment','left','Position',[0.44 0.64 0.25 0.04]);
        hChannelDelimiter = uicontrol('Style','edit','Parent',hStageControl,'String','','Units','normalized','BackgroundColor','white','Position',[0.70 0.75 0.1 0.04],'Callback',{@DelimiterChanged});
        hSliceDelimiter = uicontrol('Style','edit','Parent',hStageControl,'String','','Units','normalized','BackgroundColor','white','Position',[0.70 0.70 0.1 0.04],'Callback',{@DelimiterChanged});
        hDownsample = uicontrol('Style','edit','Parent',hStageControl,'String','32','Units','normalized','BackgroundColor','white','Position',[0.70 0.65 0.1 0.04],'Callback',{@DownsampleChanged});
        
        % Preview image
        colormap(gray);
        hPreviewAx = axes('Parent',hMainPanel,'Units','normalized','Position',[0.02 0.02 0.96 0.47],'Visible','off','Color','black');
        hPreviewImg = image(zeros(10,10),'Parent',hPreviewAx);
        set(hPreviewAx,'XTickLabel','','YTickLabel','','XTick',[],'YTick',[]);

        if isa(brain,'BrainImages')
            switch brain.ImportMode
                case 'slide'
                    set(hFilesContain,'SelectedObject',hSlideRadio);
                case 'stack'
                    set(hFilesContain,'SelectedObject',hStackRadio);                    
                case 'slice'
                    set(hFilesContain,'SelectedObject',hSliceRadio);                   
            end
            set(hChannelDelimiter,'String',brain.ChannelDelimiter);
            set(hSliceDelimiter,'String',brain.SliceDelimiter);
            set(hDownsample,'String',brain.Downsample);
            set(hAddFiles,'Enable','on');
            UpdateTable;
        else
            set(hFilesContain,'SelectedObject',[]);
        end
        
        function go = SliceSetCheck()
            if isa(ss,'SliceSet')
                if strcmp('Yes',questdlg('Making changes to import settings at this point will delete all work already made in subsequent stages. Are you sure you want to continue?'))
                    go = 1;
                    ss = 0;
                else
                    go = 0;
                end
            else
                go = 1;
            end
        end
        
        function RowSelected(source, eventdata)
            if size(eventdata.Indices,1) > 0
                % Get axis dimensions
                set(hPreviewAx,'Units','pixels');
                pos = get(hPreviewAx,'Position');
                set(hPreviewAx,'Units','normalized');
                set(hPreviewAx,'XLim',[1 pos(3)],'YLim',[1 pos(4)]);

                % Get image
                row = eventdata.Indices(end,1);
                img = brain.ImportImage(row,'import');
                 w = size(img,2);
                 h = size(img,1);

                if w/h > pos(3)/pos(4)
                    %set(hPreviewAx,'XLim',[1 w],'YLim',[1 pos(4)/pos(3)*h]);
                    margin = (pos(4)-pos(3)/w*h)/2;
                    set(hPreviewImg,'CData',img,'XData',[1 pos(3)],'YData',[margin pos(4)-margin]);
                    set(hPreviewAx,'Color','black');
                else
                    margin = (pos(3)-pos(4)/h*w)/2;
                    set(hPreviewImg,'CData',img,'XData',[margin pos(3)-margin],'YData',[1 pos(4)]);
                    set(hPreviewAx,'Color','black');
                end
            end
        end
        
        function ChannelSelected(source,eventdata)
            if SliceSetCheck
                brain.ImportChannels{eventdata.Indices(1)} = eventdata.EditData;
                % Update preview image
                RowSelected(source,eventdata);
            end
            UpdateTable;               
        end
        
        function DownsampleChanged(source,eventdata)
            newval = str2num(get(hDownsample,'String'));
            if ~isempty(newval) && floor(log2(newval))==log2(newval) && SliceSetCheck
                % Good value entered
                brain.Downsample = newval;
            else
                if isa(brain,'BrainImages')
                    set(hDownsample,'String',num2str(brain.Downsample));
                else
                    set(hDownsample,'String','32');
                end
                if ~isempty(newval) && floor(log2(newval))~=log2(newval)
                    msgbox('Downsampling rate must be a power of 2.','Error','error');
                end
            end
        end
        
        function DelimiterChanged(source,eventdata)
            if isa(brain,'BrainImages') && SliceSetCheck
                brain.ChannelDelimiter = get(hChannelDelimiter,'String');
                brain.SliceDelimiter = get(hSliceDelimiter,'String');
            end
            set(hSliceDelimiter,'String',brain.SliceDelimiter);
            set(hChannelDelimiter,'String',brain.ChannelDelimiter);    
            UpdateTable;
        end
        
        function UpdateTable()
            if isa(brain,'BrainImages')
                set(hFileTable,'Data',brain.TableArray);
                set(hFileTable,'ColumnFormat',{'char','char',[brain.ChannelList]});
            end
        end
        
        
        function AddFiles(source, eventdata)
            
            if SliceSetCheck
                [FileName,FilePath,~] = uigetfile({'*.tif; *.tiff; *.SCN' 'Brain Image Files'; '*.tif; *.tiff' 'TIFF File'; '*.SCN' 'Leica SCN File'},'MultiSelect','on');
                if iscell(FileName)
                    for i = 1:length(FileName)
                        FileName{i} = [FilePath FileName{i}];
                    end
                elseif ischar(FileName)
                    FileName = {[FilePath FileName]};
                end

                try
                    hStat = statmsg('Loading files...');
                    switch get(get(hFilesContain,'SelectedObject'),'String')
                        case 'Whole slides'
                            brain = BrainImages(FileName,'slide','ChannelDelimiter',get(hChannelDelimiter,'String'),'SliceDelimiter',get(hSliceDelimiter,'String'));
                            dat.AvailableStages = [1 1 0 0 0 0];
%                             set(hStage(2),'Enable','inactive');
%                             set(hStage(3),'Enable','off');
%                             set(hNextStage,'Enable','on');
                        case 'Slice stacks'
                            brain = BrainImages(FileName,'stack','ChannelDelimiter',get(hChannelDelimiter,'String'),'SliceDelimiter',get(hSliceDelimiter,'String'));
                            dat.AvailableStages = [1 0 0 1 0 0];
%                             set(hStage(3),'Enable','off');
%                             set(hStage(2),'Enable','off');
%                             set(hStage(4),'Enable','inactive');
%                             set(hNextStage,'Enable','on');
                        case 'Single slices'
                            brain = BrainImages(FileName,'slice','ChannelDelimiter',get(hChannelDelimiter,'String'),'SliceDelimiter',get(hSliceDelimiter,'String'));
                            dat.AvailableStages = [1 0 0 1 0 0];
%                             set(hStage(3),'Enable','off');
%                             set(hStage(2),'Enable','off');
%                             set(hStage(4),'Enable','inactive');
%                             set(hNextStage,'Enable','on');
                    end
                    brain.Downsample = str2num(get(hDownsample,'String'));

                    % Update filelist
                    UpdateTable;
                    UpdateStageList;
                    delete(hStat);
                catch
                    msgbox('Error importing images.','Error','error');
                end
            end
        end
        
        function ChangeImportMode(source, eventdata)
            if isa(brain,'BrainImages')
                if SliceSetCheck
                    switch get(eventdata.NewValue,'String')
                        case 'Whole slides'
                            brain.ImportMode = 'slide';
                            dat.AvailableStages = [1 1 0 0 0 0];
%                             set(hStage(2),'Enable','inactive');
%                             set(hStage(3),'Enable','off');
%                             set(hStage(4),'Enable','off');
                        case 'Slice stacks'
                            brain.ImportMode = 'stack';
                            dat.AvailableStages = [1 0 0 1 0 0];
%                             set(hStage(3),'Enable','off');
%                             set(hStage(2),'Enable','off');
%                             set(hStage(4),'Enable','inactive');
                        case 'Single slices'
                            brain.ImportMode = 'slice';
                            dat.AvailableStages = [1 0 0 1 0 0];
%                             set(hStage(3),'Enable','off');
%                             set(hStage(2),'Enable','off');
%                             set(hStage(4),'Enable','inactive');
                    end
                    UpdateStageList;
                    UpdateTable;
                else
                    switch brain.ImportMode
                       case 'slide'
                           set(hFilesContain,'SelectedObject',hSlideRadio);
                       case 'stack'
                           set(hFilesContain,'SelectedObject',hStackRadio);
                       case 'slice'
                           set(hFilesContain,'SelectedObject',hSliceRadio);
                    end
                end
            else
                % Enable Add Files Button

               set(hAddFiles,'Enable','on'); 
            end
        end
        
    end



    %%
    
    function [hStagePanel] = BrainSegment(hWindow,hStage,hNextStage,hPreviousStage);
        hMainPanel = uipanel('Parent',hWindow,'Units','normalized','Position',[0.015 0.02 0.62 0.96],'DeleteFcn',{@(source,eventdata) ClearROIs});
        hStageControl = uipanel('Parent',hWindow,'Units','normalized','BorderType','none','Clipping','off','Position',[0.655 0.14 0.33 0.62],'DeleteFcn',{@(source,eventdata) ClearROIs});
        hStagePanel = [hMainPanel hStageControl];
  
        if ~isa(ss,'SliceSet')
            % slices object needs to be created
            ss = SliceSet(brain);
        end
        
        % Generate gui elements for image
        hBounds = 1;
        colormap(gray);
        imrectrunning = false;
        hImgAx = axes('Parent',hMainPanel,'Units','normalized','Position',[0.02 0.02 0.96 0.96],'Visible','off','Color','black');
        hImg = image(zeros(10,10),'Parent',hImgAx);
        set(hImgAx,'XTickLabel','','YTickLabel','','XTick',[],'YTick',[]);
        
        % Generate static text for the control figure
        uicontrol('Parent',hStageControl,'Style','text','HorizontalAlignment','left','Units','normalized','Position',[0.02 0.86 0.30 0.04],'String','Threshold');
        uicontrol('Parent',hStageControl,'Style','text','HorizontalAlignment','left','Units','normalized','Position',[0.02 0.76 0.30 0.04],'String','Minimum Object Size');
        uicontrol('Parent',hStageControl,'Style','text','HorizontalAlignment','left','Units','normalized','Position',[0.02 0.66 0.30 0.04],'String','Buffer');

        % Generate sliders for the control figure
        if ss.ImageNum ~= 1
            hSlideNumSlider = uicontrol('Parent',hStageControl,'Style','Slider','Units','normalized','Position',[0.10 0.92 0.78 0.04],'Value',CurrSlide/ss.ImageNum,'Min',1/ss.ImageNum,'Max',1,'SliderStep', [1/(ss.ImageNum-1) 1/(ss.ImageNum-1)],'Callback',{@SlideChanged});
            hSlideNumDisp = uicontrol('Parent',hStageControl,'Style','text','HorizontalAlignment','left','Units','normalized','Position',[0.90 0.915 0.08 0.04],'String',num2str(CurrSlide));
            uicontrol('Parent',hStageControl,'Style','text','HorizontalAlignment','left','Units','normalized','Position',[0.02 0.96 0.30 0.04],'String','Slide');
        end
        hThresholdSlider = uicontrol('Parent',hStageControl,'Style','Slider','Units','normalized','Position',[0.10 0.82 0.78 0.04],'Value',ss.SegmentParams{CurrSlide}.Threshold/255,'Min',0,'Max',1,'SliderStep', [1/255 1/255],'Callback',{@ParamChanged});
        hMinObjSizeSlider = uicontrol('Parent',hStageControl,'Style','Slider','Units','normalized','Position',[0.10 0.72 0.78 0.04],'Value',ss.SegmentParams{CurrSlide}.MinSize/5000,'Min',0,'Max',1,'SliderStep', [10/5000 100/5000],'Callback',{@ParamChanged});
        hBufferSlider = uicontrol('Parent',hStageControl,'Style','Slider','Units','normalized','Position',[0.10 0.62 0.78 0.04],'Value',ss.SegmentParams{CurrSlide}.Buffer/100,'Min',0,'Max',1,'SliderStep', [1/100 1/100],'Callback',{@ParamChanged});
        
        % Generate text to report slider values
        hThresholdDisp = uicontrol('Parent',hStageControl,'Style','text','HorizontalAlignment','left','Units','normalized','Position',[0.90 0.815 0.08 0.04],'String',num2str(ss.SegmentParams{CurrSlide}.Threshold));
        hMinObjSizeDisp = uicontrol('Parent',hStageControl,'Style','text','HorizontalAlignment','left','Units','normalized','Position',[0.90 0.715 0.08 0.04],'String',num2str(ss.SegmentParams{CurrSlide}.MinSize));
        hBufferDisp = uicontrol('Parent',hStageControl,'Style','text','HorizontalAlignment','left','Units','normalized','Position',[0.90 0.615 0.08 0.04],'String',num2str(ss.SegmentParams{CurrSlide}.Buffer));
       
        % Generate control buttons
        hApplyAll = uicontrol('Parent',hStageControl,'Style','pushbutton','String','Apply to All','Units','normalized','Position',[0.02 0.50 0.96 0.1],'Callback',{@ApplyAll});
        hAddROI = uicontrol('Parent',hStageControl,'Style','togglebutton','String','Add ROI','Min',0,'Max',1,'Units','normalized','Position',[0.02 0.38 0.47 0.1],'Callback',{@AddDeleteROI});
        hDeleteROI = uicontrol('Parent',hStageControl,'Style','togglebutton','String','Delete ROI','Min',0,'Max',1,'Units','normalized','Position',[0.51 0.38 0.47 0.1],'Callback',{@AddDeleteROI}); 
    
        % Create initial display
        UpdateDisplay;
        StagesOff = 0;
        
        function SwitchButtonEnable
            % Function to inactivate and reactivate buttons while imrect is
            % running
            h = [hThresholdSlider,hMinObjSizeSlider,hBufferSlider,hPreviousStage,hApplyAll];
            if exist('hSlideNumSlider','var')
                h(end+1) = hSlideNumSlider;
            end
            for i = 1:length(h)
                if strcmp(get(h(i),'Enable'),'off')
                    set(h(i),'Enable','on')
                else
                    set(h(i),'Enable','off')
                end
            end
            if StagesOff
                SetStageAvailability;
                set(hStage(dat.stage),'ForegroundColor','red');
                for i=1:6
                    if dat.AvailableStages(i)
                        set(hStage(i),'Enable','inactive');
                    else
                        set(hStage(i),'Enable','off');
                    end
                end
                StagesOff = 0;
                if dat.AvailableStages(3)
                    set(hNextStage,'Enable','on');
                end
            else
                for i=1:6
                    set(hStage(i),'Enable','off');
                end
                set(hNextStage,'Enable','off');
                StagesOff = 1;
            end
        end
        
        function AddDeleteROI(source,eventdata)
            if source==hAddROI && get(hAddROI,'Value')==1
                set(hDeleteROI,'Value',0);
                
                % Get image scaling
                XData = get(hImg,'XData');
                YData = get(hImg,'YData');
                w = size(ss.BrainImagesObj.Image{CurrSlide},2);
                h = size(ss.BrainImagesObj.Image{CurrSlide},1);
                if XData(1) == 1
                    scale = XData(2)/w;
                    margin = [0 YData(1) 0 0];
                else
                    scale = YData(2)/h;
                    margin = [XData(1) 0 0 0];
                end
                SwitchButtonEnable;     % Make sure user can't press any other buttons when imrect is running
                while ishandle(hAddROI) && get(hAddROI,'Value')
                    imrectrunning = true;
                    handle = imrect(hImgAx, 'PositionConstraintFcn', @(position) NewROIChanged(position,scale, margin, w, h));
                    imrectrunning = false;
                    if ~isempty(handle)
                        pos = round((getPosition(handle)-margin)/scale);
                        ss.AddSlice(pos,CurrSlide);
                        ss.Slices{end}.Handle = handle;
                        setPositionConstraintFcn(handle,@(position) ROIBoundChanged(handle,position,scale,margin,ss.SliceNum));
                    end
                end
                SwitchButtonEnable;
            elseif source==hAddROI && get(hAddROI,'Value')==0 && imrectrunning
                robot = java.awt.Robot;
                robot.keyPress    (java.awt.event.KeyEvent.VK_ESCAPE);
                robot.keyRelease  (java.awt.event.KeyEvent.VK_ESCAPE); 
                imrectrunning = false;
            elseif source==hDeleteROI && get(hDeleteROI,'Value')==1
                if imrectrunning
                    robot = java.awt.Robot;
                    robot.keyPress    (java.awt.event.KeyEvent.VK_ESCAPE);
                    robot.keyRelease  (java.awt.event.KeyEvent.VK_ESCAPE); 
                    imrectrunning = false;
                end
                set(hAddROI,'Value',0);
            end
            
            function NewPos = NewROIChanged(NewPos,scale,margin,w,h)
                % Convert displayed image coordinates to real image
                % coordinates
                NewPos = round((NewPos-margin)/scale);

                if NewPos(1) < 1
                    NewPos(3) = NewPos(3)+NewPos(1);
                    if NewPos(3) < 0
                        NewPos(3) = 0;
                    end
                    NewPos(1) = 1;
                end
                if NewPos(1) > w
                    NewPos(1) = w;
                end
                if NewPos(2) < 1
                    NewPos(4) = NewPos(4)+NewPos(2);
                    if NewPos(4) < 0
                        NewPos(4) = 0;
                    end
                    NewPos(2) = 1;
                end
                if NewPos(2) > h
                    NewPos(2) = h;
                end
                if (NewPos(1)+NewPos(3)) > w
                    NewPos(3) = w-NewPos(1);
                end
                if (NewPos(2)+NewPos(4)) > h
                    NewPos(4) = h-NewPos(2);
                end

                % Convert back to displayed image coordinates
                NewPos = NewPos*scale+margin; 
            end
        end
        
        function ApplyAll(source,eventdata)
            if strcmp('Yes',questdlg('Are you sure you want to apply the current segmentation parameters to all slides? All other changes you"ve made will be lost.'))
                for i = 1:ss.ImageNum
                    SegmentParams{i}.Threshold = ss.SegmentParams{CurrSlide}.Threshold;
                    SegmentParams{i}.MinSize = ss.SegmentParams{CurrSlide}.MinSize;
                    SegmentParams{i}.Buffer = ss.SegmentParams{CurrSlide}.Buffer;
                end
                ss.SegmentParams = SegmentParams;
                SetStageAvailability;
            end
        end
        
        function SlideChanged(source,eventdata)
            CurrSlide = round(get(hSlideNumSlider,'Value')*ss.ImageNum);
            set(hSlideNumDisp,'String',num2str(CurrSlide));
            set(hThresholdDisp,'String',num2str(ss.SegmentParams{CurrSlide}.Threshold));
            set(hMinObjSizeDisp,'String',num2str(ss.SegmentParams{CurrSlide}.MinSize));
            set(hBufferDisp,'String',num2str(ss.SegmentParams{CurrSlide}.Buffer));
            set(hThresholdSlider,'Value',ss.SegmentParams{CurrSlide}.Threshold/255);
            set(hMinObjSizeSlider,'Value',ss.SegmentParams{CurrSlide}.MinSize/5000);
            set(hBufferSlider,'Value',ss.SegmentParams{CurrSlide}.Buffer/100);
            UpdateDisplay;
        end
        
        function ParamChanged(source,eventdata)
            ClearROIs;

            switch source
                case hThresholdSlider
                    ss.SegmentParams{CurrSlide}.Threshold = round(get(hThresholdSlider,'Value')*255);
                    set(hThresholdDisp,'String',num2str(ss.SegmentParams{CurrSlide}.Threshold));
                case hMinObjSizeSlider
                    ss.SegmentParams{CurrSlide}.MinSize = round(get(hMinObjSizeSlider,'Value')*5000);
                    set(hMinObjSizeDisp,'String',num2str(ss.SegmentParams{CurrSlide}.MinSize));
                case hBufferSlider
                    ss.SegmentParams{CurrSlide}.Buffer = round(get(hBufferSlider,'Value')*100);
                    set(hBufferDisp,'String',num2str(ss.SegmentParams{CurrSlide}.Buffer));
            end
            
             ShowROIs;
        end
        
        
        function UpdateDisplay()
            
            ClearROIs;

            % Get axis dimensions
            set(hImgAx,'Units','pixels');
            pos = get(hImgAx,'Position');
            set(hImgAx,'Units','normalized');
            set(hImgAx,'XLim',[1 pos(3)],'YLim',[1 pos(4)]);

            % Get image
            img = ss.BrainImagesObj.Image{CurrSlide};
            w = size(img,2);
            h = size(img,1);

            if w/h > pos(3)/pos(4)
                margin = (pos(4)-pos(3)/w*h)/2;
                set(hImg,'CData',img,'XData',[1 pos(3)],'YData',[margin pos(4)-margin]);
                set(hImgAx,'Color','black');
            else
                margin = (pos(3)-pos(4)/h*w)/2;
                set(hImg,'CData',img,'XData',[margin pos(3)-margin],'YData',[1 pos(4)]);
                set(hImgAx,'Color','black');
            end 
            
            ShowROIs;
        end
        
        function ClearROIs()
            for i = 1:ss.SliceNum
                if ~isempty(ss.Slices{i}.Handle)
                    delete(ss.Slices{i}.Handle);
                    ss.Slices{i}.Handle = [];
                end
            end
        end
        
        function SetStageAvailability
           allordered = 1;
           for i = 1:ss.SliceNum
               if isempty(ss.Slices{i}.Order)
                   allordered = 0;
               end
           end
           
           if ss.SliceNum > 0
               dat.AvailableStages(3) = 1;
               set(hStage(3),'Enable','inactive');
               set(hNextStage,'Enable','on');
               if allordered
                   dat.AvailableStages(4:6) = [1 1 1];
                   for i = 4:6
                       set(hStage(i),'Enable','inactive');
                   end
               else
                   dat.AvailableStages(4:6) = [0 0 0];
                   for i = 4:6
                       set(hStage(i),'Enable','off');
                   end
               end
           else
               dat.AvailableStages(3) = 0;
               set(hStage(3),'Enable','off');
               set(hNextStage,'Enable','off');
           end
        end
        
        function ShowROIs()  
            
           % Set availability of next stage
            SetStageAvailability;
            
           % Get image scaling
           XData = get(hImg,'XData');
           YData = get(hImg,'YData');
           if XData(1) == 1
               scale = XData(2)/size(ss.BrainImagesObj.Image{CurrSlide},2);
               margin = [0 YData(1) 0 0];
           else
               scale = YData(2)/size(ss.BrainImagesObj.Image{CurrSlide},1);
               margin = [XData(1) 0 0 0];
           end
           
           for i = 1:ss.SliceNum
                if ss.Slices{i}.FileGroupID == CurrSlide
                    ss.Slices{i}.Handle = imrect(hImgAx,ss.Slices{i}.Position*scale+margin);
                    h = ss.Slices{i}.Handle;
                    setPositionConstraintFcn(ss.Slices{i}.Handle,@(position) ROIBoundChanged(h,position,scale,margin,i));
                end
           end        
            
        end
        
        function NewPos = ROIBoundChanged(handle,NewPos,scale,margin,SliceID)
            
            if get(hDeleteROI,'Value')
                % Clear orders for all slices on this slide
           
                for i=1:ss.SliceNum
                    if ss.Slices{i}.FileGroupID==CurrSlide
                        ss.Slices{i}.Order = [];
                        % Correct index passed to PositionConstraintFcn
                        if i>SliceID
                            h = ss.Slices{i}.Handle;
                            setPositionConstraintFcn(ss.Slices{i}.Handle,@(position) ROIBoundChanged(h,position,scale,margin,i-1));
                        end
                    end
                end
                SetStageAvailability;
                delete(handle);
                ss.DeleteSliceByHandle(handle);
            else
            
                % Convert new position to real image coordinates
                NewPos = round((NewPos-margin)/scale);
                OldPos = round(ss.Slices{SliceID}.Position);

                % Get image width and height
                w = size(ss.BrainImagesObj.Image{CurrSlide},2);
                h = size(ss.BrainImagesObj.Image{CurrSlide},1);

                % Make new position is within bounds of the slide
                if NewPos(1) < 1
                    if NewPos(3)==OldPos(3)
                        % The whole ROI is being dragged
                        NewPos(3) = OldPos(3);
                        NewPos(1) = 1;
                    else
                        % The left handle is being dragged
                        NewPos(3) = NewPos(3)+NewPos(1)-1;
                        NewPos(1) = 1;
                    end
                end
                if NewPos(2) < 1
                    if NewPos(4)==OldPos(4)
                        % The whole ROI is being dragged
                        NewPos(4) = OldPos(4);
                        NewPos(2) = 1;
                    else
                        % The top handle is being dragged
                        NewPos(4) = NewPos(4)+NewPos(2)-1;
                        NewPos(2) = 1;
                    end
                end
                if (NewPos(1)+NewPos(3)-1) > w
                    if NewPos(1)==OldPos(1)
                        % The right handle is being dragged
                        NewPos(3) = w-NewPos(1)+1;
                        %disp('here');
                    else
                        % The whole ROI is being dragged
                        NewPos(3) = OldPos(3);
                        NewPos(1) = w-NewPos(3)+1;
                    end
                end
                if (NewPos(2)+NewPos(4)-1) > h
                    if NewPos(2)==OldPos(2)
                        % The bottom handle is being dragged
                        NewPos(4) = h-NewPos(2)+1;
                    else
                        % The whole ROI is being dragged
                        NewPos(4) = OldPos(4);
                        NewPos(2) = h-NewPos(4)+1;
                    end
                end

                % Store new coordinates
                ss.Slices{SliceID}.Position = NewPos;
                ss.Slices{SliceID}.Order = [];

                % Convert back to displayed image space
                NewPos = NewPos*scale+margin;
            end
            SetStageAvailability;
        end
        
        



            

    end


%%
    function [hStagePanel] = BrainOrder(hWindow,hStage,hNextStage,hPreviousStage)
        hMainPanel = uipanel('Parent',hWindow,'Units','normalized','Position',[0.015 0.02 0.62 0.96],'DeleteFcn',@(source,eventdata) ClearROIs);
        hStageControl = uipanel('Parent',hWindow,'Units','normalized','BorderType','none','Clipping','off','Position',[0.655 0.14 0.33 0.62],'DeleteFcn',@(source,eventdata) ClearROIs);
        hStagePanel = [hMainPanel hStageControl];

        % Generate slide change slider
        if ss.ImageNum ~= 1
            hSlideNumSlider = uicontrol('Parent',hStageControl,'Style','Slider','Units','normalized','Position',[0.10 0.92 0.78 0.04],'Value',CurrSlide/ss.ImageNum,'Min',1/ss.ImageNum,'Max',1,'SliderStep', [1/(ss.ImageNum-1) 1/(ss.ImageNum-1)],'Callback',{@SlideChanged});    
            hSlideNumDisp = uicontrol('Parent',hStageControl,'Style','text','HorizontalAlignment','left','Units','normalized','Position',[0.90 0.915 0.08 0.04],'String',num2str(CurrSlide));
            uicontrol('Parent',hStageControl,'Style','text','HorizontalAlignment','left','Units','normalized','Position',[0.02 0.96 0.30 0.04],'String','Slide');
        end
        
        % Create axis object to hold boundary points
        hbpAx = axes('Parent',hMainPanel,'Units','normalized','Position',[0.02 0 0.96 0.01],'Visible','off','Color','black','XTickLabel','','YTickLabel','','XTick',[],'YTick',[],'XLim',[0 1],'YLim',[0 1]);
        hAddPt = uicontrol('Parent',hStageControl,'Style','pushbutton','String','Add Boundary Point','Min',0,'Max',1,'Units','normalized','Position',[0.02 0.78 0.47 0.1],'Callback',{@ChangePtNum});
        hDeletePt = uicontrol('Parent',hStageControl,'Style','pushbutton','String','Remove Boundary Point','Min',0,'Max',1,'Units','normalized','Position',[0.51 0.78 0.47 0.1],'Callback',{@ChangePtNum}); 
        
        % Create arrangement selection objects
        % x(1) y(1) x(2) y(2)
        uicontrol('Parent',hStageControl,'Style','text','HorizontalAlignment','left','Units','normalized','Position',[0.02 0.72 0.30 0.04],'String','Section Arrangement');
        arr =   [0 0 0 1 1 0 1 1; ...
                 0 1 0 0 1 1 1 0; ...
                 0 0 0 1 1 1 1 0; ...
                 0 1 0 0 1 0 1 1; ...
                 1 0 1 1 0 0 0 1; ...
                 1 1 1 0 0 1 0 0; ...
                 1 1 1 0 0 0 0 1; ...
                 1 0 1 1 0 1 0 0];
        arr = arr*0.6+0.2;
        
        for i = 1:size(arr,1)
            if i <= 4
                hArrAx(i) = axes('Parent',hStageControl,'Units','normalized','Position', [0.1+(i-1)*0.22 0.51 0.2 0.2],'Color','white','XTickLabel','','YTickLabel','','XTick',[],'YTick',[],'XLim',[0 1],'YLim',[0 1],'XColor','white','YColor','white','ButtonDownFcn',{@ArrSelected});
            else
                hArrAx(i) = axes('Parent',hStageControl,'Units','normalized','Position', [0.1+(i-5)*0.22 0.29 0.2 0.2],'Color','white','XTickLabel','','YTickLabel','','XTick',[],'YTick',[],'XLim',[0 1],'YLim',[0 1],'XColor','white','YColor','white','ButtonDownFcn',{@ArrSelected});
            end
            for j = [1 3 5];
                hArrow = annotation('arrow',[arr(i,j) arr(i,j+2)],[arr(i,j+1) arr(i,j+3)],'HeadStyle','plain','HeadWidth',10,'HeadLength',10,'LineWidth',2);
                set(hArrow,'parent',hArrAx(i),'HitTest','off');
            end
        end
        
        % Load slice images
        hStat = statmsg('Loading slice images...');
        ss.LoadSliceImages;
        delete(hStat);
        
        % Calculate axis positions ROIs that don't already have it defined
        pos = [0.02 0.02 0.96 0.96];
        for i = 1:ss.SliceNum
            if isempty(ss.Slices{i}.OrderAxPos)
                % Get image scaling properties    
                w = size(ss.BrainImagesObj.Image{ss.Slices{i}.FileGroupID},2);
                h = size(ss.BrainImagesObj.Image{ss.Slices{i}.FileGroupID},1);

                if w/h > pos(3)/pos(4)
                    scale = pos(3)/w;
                    margin = [pos(1) (pos(4)-h*scale)/2+pos(2) 0 0]; 
                else
                    scale = pos(4)/h;               
                    margin = [(pos(3)-w*scale)/2+pos(1) pos(2) 0 0];
                end 
                AxPos = ss.Slices{i}.Position;
                AxPos(2) = h-AxPos(2)-AxPos(4);                 % Necessary because ROI coordinates have the origin in the upper-left corner, while figures have origin in lower-left corner
                ss.Slices{i}.OrderAxPos = AxPos*scale+margin;
            end
        end
        
        % Get initial slice order
        for i = 1:ss.ImageNum
            if ~iscell(ss.BoundaryPts) || i > length(ss.BoundaryPts) || isempty(ss.BoundaryPts{i})
                BoundaryPts{i} = [0 0.5 1];
            else
                BoundaryPts{i} = ss.BoundaryPts{i};
            end
        end
        ss.BoundaryPts = BoundaryPts;
        
        % Get initial slice arrangement
        for i = 1:ss.ImageNum
             if i > length(ss.SliceArr) || isempty(ss.SliceArr(i))
                SliceArr(i) = 1;
            else
                SliceArr(i) = ss.SliceArr(i);
            end           
        end
        ss.SliceArr = SliceArr;
        
        % Once the above work is done, then make other stages available
        dat.AvailableStages(4:6) = [1 1 1];
        for i = 4:6
            set(hStage(i),'Enable','inactive');
        end
        set(hNextStage,'Enable','on');
        
        % Set variables necessary for dragging ROIs
        CurrDrag = 0;
        MouseStartPos = 0;
        AxisStartPos = 0;
        WindowPos = 0;
        hbp = 0;
        
        colormap(gray);     
        UpdateDisplay;
        UpdateBounds;
        ArrSelected(hArrAx(ss.SliceArr(CurrSlide)),0);
        
        function ArrSelected(source,eventdata)
            % Clear selection of all other arrangement icons
            for i = 1:length(hArrAx)
                set(hArrAx(i),'Box','off','XColor','white','YColor','white','LineWidth',1.5);
            end
            
            % Set box for selected icon to 'on'
            ss.SliceArr(CurrSlide) = find(hArrAx==source);
            set(source,'Box','on','XColor','green','YColor','green','LineWidth',1.5);
            UpdateOrderLabels;
        end
        
        function ChangePtNum(source,eventdata)
            bp = sort(ss.BoundaryPts{CurrSlide});
            if source==hAddPt
                ss.BoundaryPts{CurrSlide} = [ss.BoundaryPts{CurrSlide}(1) bp(1)+bp(2)/2 ss.BoundaryPts{CurrSlide}(2:end)];
            else
                if length(bp) > 2
                    ss.BoundaryPts{CurrSlide}(find(bp(2)==ss.BoundaryPts{CurrSlide},1,'first')) = [];
                end
            end
            UpdateBounds;
            UpdateOrderLabels;
        end
        
        function UpdateBounds()
            
            % Clear old boundary points
            if isa(hbp(1),'impoint');
                for i = 1:length(hbp)
                    delete(hbp(i));
                end
            end
            
            % Create boundary points
            hbp = impoint.empty(length(ss.BoundaryPts{CurrSlide}),0);
            for i = 1:length(ss.BoundaryPts{CurrSlide})
                hbp(i) = impoint(hbpAx,ss.BoundaryPts{CurrSlide}(i),0.4,'PositionConstraintFcn',@(position) BoundConstraint(position,i));
            end
            
            function NewPos = BoundConstraint(NewPos,bpid)
                NewPos(2) = 0.5;
                if NewPos(1) < 0
                    NewPos(1) = 0;
                elseif NewPos(1) > 1
                    NewPos(1) = 1;
                end
                ss.BoundaryPts{CurrSlide}(bpid) = NewPos(1);
                UpdateOrderLabels;
            end
        end
            
    
        function SlideChanged(source,eventdata)
            CurrSlide = round(get(hSlideNumSlider,'Value')*ss.ImageNum);
            set(hSlideNumDisp,'String',num2str(CurrSlide));
            UpdateDisplay;
            UpdateBounds;
            ArrSelected(hArrAx(ss.SliceArr(CurrSlide)),0)
        end       
        
        function ClearROIs()
            for i = 1:ss.SliceNum
                if ~isempty(ss.Slices{i}.Handle)
                    if ishandle(ss.Slices{i}.Handle)
                        delete(ss.Slices{i}.Handle);
                    end
                    ss.Slices{i}.Handle = [];
                    ss.Slices{i}.HandleB = [];
                end
            end
        end
        
        function UpdateOrderLabels()
            for i = 1:ss.SliceNum
                if ~isempty(ss.Slices{i}.Handle)
                    set(ss.Slices{i}.HandleB,'String',num2str(ss.Slices{i}.Order));
                end
            end
        end

        function UpdateDisplay()
            
            % Clear all prior axes if there were any
            ClearROIs; 
            
            % Create axes/images for each ROI on the current slide
            for i = 1:ss.SliceNum
                if ss.Slices{i}.FileGroupID == CurrSlide
                    ss.Slices{i}.Handle = axes('Parent',hMainPanel,'Units','normalized','Position',ss.Slices{i}.OrderAxPos);
                    image(ss.Slices{i}.Image,'Parent',ss.Slices{i}.Handle,'HitTest','off');
                    set(ss.Slices{i}.Handle,'XTickLabel','','YTickLabel','','ButtonDownFcn',@StartDrag);
                    set(ss.Slices{i}.Handle,'HitTest','on');
                    ss.Slices{i}.HandleB = text(10,10,num2str(ss.Slices{i}.Order),'BackgroundColor','red','VerticalAlignment','top');
                end
            end   
            % hAxText(i) = text(10,10,num2str(i),'BackgroundColor','red','VerticalAlignment','top');
 
            function StartDrag(source, eventdata)
                % Define callback functions for when the cursor moves and when the
                % mouse botton is released
                set(hWindow,'WindowButtonMotionFcn',@Drag);
                set(hWindow,'WindowButtonUpFcn',@EndDrag);

                % Set variable to hold handle of axis being dragged
                CurrDrag = source;

                % Get Window position
                WindowPos = getpixelposition(hMainPanel);
                
                % Store cursor position when the mouse was clicked and the starting
                % position of the axis object
                MouseStartPos = get(hWindow,'CurrentPoint');
                MouseStartPos = [MouseStartPos(1)/WindowPos(3) MouseStartPos(2)/WindowPos(4)];
                AxisStartPos = get(CurrDrag,'Position');
            end

            function Drag(source, eventdata)
                % Calculate new axis position
                CurrMousePos = get(hWindow,'CurrentPoint');
                CurrMousePos = [CurrMousePos(1)/WindowPos(3) CurrMousePos(2)/WindowPos(4)];
                NewPos = [AxisStartPos(1)+CurrMousePos(1)-MouseStartPos(1) ...
                    AxisStartPos(2)+CurrMousePos(2)-MouseStartPos(2) ...
                    AxisStartPos(3) AxisStartPos(4)];

                % Update axis position
                set(CurrDrag,'Position',NewPos);

            end

            function EndDrag(source, eventdata)
                % Clear callback functions for mouse movement and button release
                set(hWindow,'WindowButtonMotionFcn','');
                set(hWindow,'WindowButtonUpFcn','');

                for i = 1:ss.SliceNum
                    if ss.Slices{i}.Handle==CurrDrag
                        ss.Slices{i}.OrderAxPos = get(CurrDrag,'Position');
                    end
                end

                % Re-calculate order
                ss.SortSlices;
                UpdateOrderLabels;
            end    
        end    
    end

%%
    function [ hStagePanel ] = BrainPreprocess(hWindow,hStage,hNextStage,hPreviousStage)
        hMainPanel = uipanel('Parent',hWindow,'Units','normalized','Position',[0.015 0.02 0.62 0.96]);            % 'DeleteFcn',@(source,eventdata) ClearROIs);
        hStageControl = uipanel('Parent',hWindow,'Units','normalized','BorderType','none','Clipping','off','Position',[0.655 0.14 0.33 0.62]);               % 'DeleteFcn',@(source,eventdata) ClearROIs);
        hStagePanel = [hMainPanel hStageControl];
        
        if ~isa(ss,'SliceSet')
             % ss hasn't been created--single slice or stack images
            ss = SliceSet(brain);
            
            % Generate slice objects
            ss.Slices = [];
            if strcmp(ss.BrainImagesObj.ImportMode,'slice')
                for i = 1:ss.ImageNum
                    ss.AddSlice([1 1 size(ss.BrainImagesObj.Image{i},2) size(ss.BrainImagesObj.Image{i},1)],i);
                    ss.Slices{i}.Order = i;
                end
                ss.LoadSliceImages;
            elseif strcmp(ss.BrainImagesObj.ImportMode,'stack')
                % Get the number of slices in each file

                for i = 1:ss.ImageNum
                    switch ss.BrainImagesObj.ReadMode
                        case 'across'  
                            fin = ss.BrainImagesObj.FileGroups{i,find(strcmp(ss.BrainImagesObj.ChInFile(i,:),ss.BrainImagesObj.ImportChannels{i}))};   
                        case {'single','RGB'}
                            fin = ss.BrainImagesObj.FileGroups{i,1};
                    end
                    info = imfinfo(fin);
                    snum(i) = length(info);
                end

                imgtotal = sum(snum);
                hWait = waitbar(0,'Loading images...','WindowStyle','modal');
                for i = 1:ss.ImageNum
                    for j = 1:snum(i)
                        waitbar(length(ss.Slices)/imgtotal,hWait);
                        img = ss.BrainImagesObj.ImportImage(i,ss.BrainImagesObj.ImportChannels{i},j);
                        ss.Slices{end+1} = SingleSlice([1 1 size(img,2) size(img,1)],i);
                        ss.Slices{end}.ImgIndex = j;
                        ss.Slices{end}.Image = img;
                        ss.Slices{end}.Order = length(ss.Slices);
                    end
                end
                delete(hWait);
            end
            dat.AvailableStages(5:6) = [1 1];
            set(hStage(5),'Enable','inactive');
            set(hStage(6),'Enable','inactive');
            set(hNextStage,'Enable','on');
        end
        
        % Setup range indicator colormap
        rangecolor = gray;
        rangecolor(1,:) = [1 0 0];
        rangecolor(255,:) = [0 0 1];
        colormap(gray);
        
        % Re-order slice array
        ss.ReorderSliceArray;
        
        % Create axes to hold unprocessed and processed image
        hOrAx = axes('Parent',hMainPanel,'Units','normalized','Position',[0 0 0.5 1],'Visible','off','Color','black');
        hPrAx = axes('Parent',hMainPanel,'Units','normalized','Position',[0.5 0 0.5 1],'Visible','off','Color','black');
        hOrImg = image(zeros(10,10),'Parent',hOrAx);
        hPrImg = image(zeros(10,10),'Parent',hPrAx);
        set(hOrAx,'XTickLabel','','YTickLabel','','XTick',[],'YTick',[]);
        set(hPrAx,'XTickLabel','','YTickLabel','','XTick',[],'YTick',[]);
        
        % Generate controls
        % Image histogram
        hHistAx = axes('Parent',hStageControl,'Units','normalized','Position', [0.02 0.5 0.96 0.2],'Color','white');   
        hHistBar = bar(hHistAx,[0:255],ones(256,1),'FaceColor',[0 0 0]);
        hConA = imline(hHistAx,[ss.Slices{CurrSlice}.CleanParams.ContrastMin 0; ss.Slices{CurrSlice}.CleanParams.ContrastMin 1]);
        hConB = imline(hHistAx,[ss.Slices{CurrSlice}.CleanParams.ContrastMax 0; ss.Slices{CurrSlice}.CleanParams.ContrastMax 1]);
        setPositionConstraintFcn(hConA,@(pos) ConstrainContrast(pos,hConA));
        setPositionConstraintFcn(hConB,@(pos) ConstrainContrast(pos,hConB));
        
        % Buttons
        uicontrol('Parent',hStageControl,'Style','pushbutton','String','Apply to All','Units','normalized','Position',[0.02 0.38 0.3 0.1],'Callback',{@ApplyAll});
        hAutoContrast = uicontrol('Parent',hStageControl,'Style','togglebutton','String','Auto Contrast','Min',0,'Max',1,'Value',ss.Slices{CurrSlice}.CleanParams.AutoContrast,'Units','normalized','Position',[0.34 0.38 0.3 0.1],'Callback',{@AutoContrast});
        hDeleteSlice = uicontrol('Parent',hStageControl,'Style','pushbutton','String','Delete Slice','Units','normalized','Position',[0.66 0.38 0.3 0.1],'Callback',{@DeleteSlice});
        uicontrol('Parent',hStageControl,'Style','pushbutton','String','Draw Mask','Units','normalized','Position',[0.02 0.27 0.47 0.1],'Callback',{@DrawMask});
        
        % Range indicator checkbox
        hRange = uicontrol('Parent',hStageControl,'Style','checkbox','String','Range Indicator','Min',0,'Max',1,'Value',0,'Units','normalized','Position',[0.62 0.29 0.3 0.05],'Callback',{@RangeIndicator});
        
        % Slice change slider
        uicontrol('Parent',hStageControl,'Style','text','HorizontalAlignment','left','Units','normalized','Position',[0.02 0.96 0.30 0.04],'String','Slice');
        hSliceNumSlider = uicontrol('Parent',hStageControl,'Style','Slider','Units','normalized','Position',[0.10 0.92 0.78 0.04],'Value',CurrSlice/ss.SliceNum,'Min',1/ss.SliceNum,'Max',1,'SliderStep', [1/(ss.SliceNum-1) 1/(ss.SliceNum-1)],'Callback',{@SliceChanged});
        hSliceNumDisp = uicontrol('Parent',hStageControl,'Style','text','HorizontalAlignment','left','Units','normalized','Position',[0.90 0.915 0.08 0.04],'String',num2str(CurrSlice));
        
        % Mask threshold
        uicontrol('Parent',hStageControl,'Style','text','HorizontalAlignment','left','Units','normalized','Position',[0.02 0.86 0.30 0.04],'String','Mask Threshold');
        hMaskThreshold = uicontrol('Parent',hStageControl,'Style','Slider','Units','normalized','Position',[0.10 0.82 0.78 0.04],'Value',ss.Slices{CurrSlice}.CleanParams.MaskThreshold/255,'Min',0,'Max',1,'SliderStep', [1/255 1/255],'Callback',{@ParamChanged});
        hMaskThresholdDisp = uicontrol('Parent',hStageControl,'Style','text','HorizontalAlignment','left','Units','normalized','Position',[0.90 0.815 0.08 0.04],'String',num2str(ss.Slices{CurrSlice}.CleanParams.MaskThreshold));       
        
        % Filter objects smaller than
        uicontrol('Parent',hStageControl,'Style','text','HorizontalAlignment','left','Units','normalized','Position',[0.02 0.76 0.60 0.04],'String','Filter Objects Smaller Than...');
        hMinSize = uicontrol('Parent',hStageControl,'Style','Slider','Units','normalized','Position',[0.10 0.72 0.78 0.04],'Value',ss.Slices{CurrSlice}.CleanParams.MinSize/5000,'Min',1/5000,'Max',1,'SliderStep', [1/4999 1/4999],'Callback',{@ParamChanged});
        hMinSizeDisp = uicontrol('Parent',hStageControl,'Style','text','HorizontalAlignment','left','Units','normalized','Position',[0.90 0.715 0.08 0.04],'String',num2str(ss.Slices{CurrSlice}.CleanParams.MinSize));
        

        % Initially process all slices
        for i = 1:ss.SliceNum
            ss.Slices{i}.ProcessImage;
        end

        % Set initial conditions
        SliceChanged;
        
        function RangeIndicator(source,eventdata)
            if get(hRange,'Value')
                colormap(rangecolor);
            else
                colormap(gray);
            end
        end
        
        function DrawMask(source,eventdata)
            hFree = imfreehand(hOrAx);
            if ~isempty(hFree)
                ss.Slices{CurrSlice}.CleanParams.ManualMask = 1;
                ss.Slices{CurrSlice}.Mask = createMask(hFree);
                delete(hFree);
                ss.Slices{CurrSlice}.ProcessImage;
                UpdateImage(hPrImg,ss.Slices{CurrSlice}.ProcImg);
                UpdateHist;
            end
        end
 
        function DeleteSlice(source,eventdata)
            if ss.SliceNum > 2 && strcmp('Yes',questdlg('Are you sure you want to delete this slice?'))
                ss.DeleteSlice(CurrSlice);
                if CurrSlice>ss.SliceNum
                    CurrSlice = ss.SliceNum;
                end
                set(hSliceNumSlider,'Value',CurrSlice/ss.SliceNum,'Min',1/ss.SliceNum,'Max',1,'SliderStep', [1/(ss.SliceNum-1) 1/(ss.SliceNum-1)]);
                SliceChanged;
            end
        end
        
        function ApplyAll(source,eventdata)
            if strcmp('Yes',questdlg('Are you sure you want to apply the current processing parameters to all slides? All other changes you"ve made will be lost.'))
                for i = 1:ss.SliceNum
                    ss.Slices{i}.CleanParams = ss.Slices{CurrSlice}.CleanParams;
                    ss.Slices{i}.ProcessImage;  
                end
            end
        end
        
        function AutoContrast(source,eventdata)
            ss.Slices{CurrSlice}.CleanParams.AutoContrast = get(hAutoContrast,'Value');
            ss.Slices{CurrSlice}.ProcessImage;
            ParamChanged;
        end
        
        function pos = ConstrainContrast(pos,h)
            
            % Constrain y-axis position
            histy = ylim(hHistAx);
            pos(1,2)=0;
            pos(2,2)=histy(2);
            
            pos = round(pos);
            if pos(1,1)~=ss.Slices{CurrSlice}.CleanParams.ContrastMin && pos(1,1)~=ss.Slices{CurrSlice}.CleanParams.ContrastMax
                pos(2,1)=pos(1,1);
            else
                pos(1,1)=pos(2,1);
            end
            if pos(1,1) < 0
                pos(:,1) = [0; 0];
            end
            if pos(1,1) > 255
                pos(:,1) = [255; 255];
            end
            
            % Turn off auto-contrast
            ss.Slices{CurrSlice}.CleanParams.AutoContrast = 0;
            set(hAutoContrast,'Value',0);
            if h==hConA
                ss.Slices{CurrSlice}.CleanParams.ContrastMin = pos(1,1);
            elseif h==hConB
                ss.Slices{CurrSlice}.CleanParams.ContrastMax = pos(1,1);
            end
            ParamChanged;
        end
        
        function ParamChanged(varargin)
            if nargin==2
                % Function called by slider callback rather than
                % programatically
                ss.Slices{CurrSlice}.CleanParams.ManualMask = 0;
            end
            ss.Slices{CurrSlice}.CleanParams.MaskThreshold = round(get(hMaskThreshold,'Value')*255);
            ss.Slices{CurrSlice}.CleanParams.MinSize = round(get(hMinSize,'Value')*5000);
            set(hMaskThresholdDisp,'String',num2str(ss.Slices{CurrSlice}.CleanParams.MaskThreshold));
            set(hMinSizeDisp,'String',num2str(ss.Slices{CurrSlice}.CleanParams.MinSize));
            ss.Slices{CurrSlice}.ProcessImage;
            UpdateImage(hPrImg,ss.Slices{CurrSlice}.ProcImg);
            UpdateHist;
        end
        
        
        function UpdateHist()
            pixels = [ss.Slices{CurrSlice}.Image(:)].*[ss.Slices{CurrSlice}.Mask(:)];
            n = hist(pixels,256);
            cutbins = find(n>=0.9*max(n));          % Cut off top 10% most populated bins
            for i = 1:length(cutbins)
                pixels(pixels==(cutbins(i)-1)) = [];
            end
            n = hist(pixels,256);
            set(hHistBar,'YData',n);
            set(hHistAx,'XTickLabel','','YTickLabel','','XTick',[],'YTick',[],'Box','on','XLim',[0 255],'YLim',[0 max(n)]);
            histy=ylim(hHistAx);
            setPosition(hConA,[ss.Slices{CurrSlice}.CleanParams.ContrastMin 0; ss.Slices{CurrSlice}.CleanParams.ContrastMin histy(2)]);
            setPosition(hConB,[ss.Slices{CurrSlice}.CleanParams.ContrastMax 0; ss.Slices{CurrSlice}.CleanParams.ContrastMax histy(2)]);
        end
        
        function SliceChanged(varargin)
            CurrSlice = round(get(hSliceNumSlider,'Value')*ss.SliceNum);
            set(hSliceNumDisp,'String',num2str(CurrSlice));
            set(hMaskThreshold,'Value',ss.Slices{CurrSlice}.CleanParams.MaskThreshold/255);
            set(hMaskThresholdDisp,'String',num2str(ss.Slices{CurrSlice}.CleanParams.MaskThreshold));
            set(hMinSize,'Value',ss.Slices{CurrSlice}.CleanParams.MinSize/5000);
            set(hMinSizeDisp,'String',num2str(ss.Slices{CurrSlice}.CleanParams.MinSize));
            set(hAutoContrast,'Value',ss.Slices{CurrSlice}.CleanParams.AutoContrast);
            UpdateImage(hOrImg,ss.Slices{CurrSlice}.Image);
            UpdateImage(hPrImg,ss.Slices{CurrSlice}.ProcImg);
            UpdateHist;
        end
            
        function UpdateImage(hImg,img)
            
            % Get axis dimensions
            hAx = get(hImg,'Parent');
            pos = getpixelposition(hAx); 
            set(hAx,'XLim',[1 pos(3)],'YLim',[1 pos(4)]);
            
            % Get image dimensions
            w = size(img,2);
            h = size(img,1);

            % Get rid of 0 and 255 values in image if it's going to be
            % displayed on original image axes to prevent display of the
            % red and blue range indicator
            if hImg == hOrImg
                img(find(img<=1)) = 2;
                img(find(img>=255)) = 254;
            end
            
            if w/h > pos(3)/pos(4)
                margin = (pos(4)-pos(3)/w*h)/2;
                set(hImg,'CData',img,'XData',[1 pos(3)],'YData',[margin pos(4)-margin]);
                set(hAx,'Color','black');
            else
                margin = (pos(3)-pos(4)/h*w)/2;
                set(hImg,'CData',img,'XData',[margin pos(3)-margin],'YData',[1 pos(4)]);
                set(hAx,'Color','black');
            end
            
        end
        
    end

    %%
    function [ hStagePanel ] = BrainAlign(hWindow,hStage,hNextStage,hPreviousStage)
        hMainPanel = uipanel('Parent',hWindow,'Units','normalized','Position',[0.015 0.02 0.62 0.96],'DeleteFcn',{@cleanup});
        hStageControl = uipanel('Parent',hWindow,'Units','normalized','BorderType','none','Clipping','off','Position',[0.655 0.14 0.33 0.65],'DeleteFcn',{@cleanup});
        hStagePanel = [hMainPanel hStageControl];
        
        % Setup range indicator colormap
        colormap(gray);
        
        % Re-order slice array
        ss.ReorderSliceArray;
        
        % Set default seed if necessary
        if isempty(ss.Seed)
            ss.Seed = round(ss.SliceNum/2);
        end
        
        % Create axes to hold image
        hAx = axes('Parent',hMainPanel,'Units','normalized','Position',[0 0 1 1],'Visible','off','Color','black');
        hImg = image(zeros(10,10),'Parent',hAx,'HitTest','off');
        set(hAx,'XTickLabel','','YTickLabel','','XTick',[],'YTick',[],'HitTest','on','ButtonDownFcn',@StartDrag);
        
        % Generate controls
        % Slice change slider
        uicontrol('Parent',hStageControl,'Style','text','HorizontalAlignment','left','Units','normalized','Position',[0.02 0.945 0.30 0.04],'String','Slice');
        hSliceNumSlider = uicontrol('Parent',hStageControl,'Style','Slider','Units','normalized','Position',[0.10 0.95 0.78 0.04],'Value',CurrSlice/ss.SliceNum,'Min',1/ss.SliceNum,'Max',1,'SliderStep', [1/(ss.SliceNum-1) 1/(ss.SliceNum-1)],'Callback',{@SliceChanged});
        hSliceNumDisp = uicontrol('Parent',hStageControl,'Style','text','HorizontalAlignment','left','Units','normalized','Position',[0.90 0.945 0.08 0.04],'String',num2str(CurrSlice));

        % Checkboxes
        hShowPrev = uicontrol('Parent',hStageControl,'Style','checkbox','String','Show previous slice','Min',0,'Max',1,'Value',0,'Units','normalized','Position',[0.02 0.67 0.96 0.04],'Callback',{@UpdateImage});
        hApplyTo = uibuttongroup('Parent',hStageControl,'Units','normalized','Position',[0.02 0.72 0.96 0.2],'Title','Apply transformations to:','SelectionChangeFcn',{@ChangeApplyTo});
        uicontrol('Style','radiobutton','Parent',hApplyTo,'Units','normalized','Position',[0.05 0.78 0.9 0.2],'String','This slice only');
        uicontrol('Style','radiobutton','Parent',hApplyTo,'Units','normalized','Position',[0.05 0.54 0.9 0.2],'String','All subsequent slices');
        uicontrol('Style','radiobutton','Parent',hApplyTo,'Units','normalized','Position',[0.05 0.30 0.9 0.2],'String','All previous slices');
        uicontrol('Style','radiobutton','Parent',hApplyTo,'Units','normalized','Position',[0.05 0.06 0.9 0.2],'String','All slices');
        
        % Buttons
        hUndo = uicontrol('Parent',hStageControl,'Style','pushbutton','String','Undo','Units','normalized','Position',[0.02 0.55 0.305 0.1],'Enable','off','Callback',{@Undo});
        hRedo = uicontrol('Parent',hStageControl,'Style','pushbutton','String','Redo','Units','normalized','Position',[0.35 0.55 0.305 0.1],'Enable','off','Callback',{@Redo});
        uicontrol('Parent',hStageControl,'Style','pushbutton','String','Delete Slice','Units','normalized','Position',[0.68 0.55 0.305 0.1],'Callback',{@DeleteSlice});
        hFlipH = uicontrol('Parent',hStageControl,'Style','pushbutton','String','Flip Horizontally','Units','normalized','Position',[0.02 0.43 0.305 0.1],'Callback',{@transform});
        hFlipV = uicontrol('Parent',hStageControl,'Style','pushbutton','String','Flip Vertically','Units','normalized','Position',[0.35 0.43 0.305 0.1],'Callback',{@transform});
        hSeed = uicontrol('Parent',hStageControl,'Style','pushbutton','String',['Reset Seed (' num2str(ss.Seed) ')'],'Units','normalized','Position',[0.68 0.43 0.305 0.1],'Callback',{@SetSeed});
        uicontrol('Parent',hStageControl,'Style','pushbutton','String','Auto-rotate and Center','Units','normalized','Position',[0.02 0.31 0.47 0.1],'Callback',{@AutoRotateCenter});
        uicontrol('Parent',hStageControl,'Style','pushbutton','String','Automatic Rigid Alignment','Units','normalized','Position',[0.51 0.31 0.47 0.1],'Callback',{@Rigid});
        uicontrol('Parent',hStageControl,'Style','pushbutton','String','Automatic Non-rigid Alignment','Units','normalized','Position',[0.02 0.19 0.47 0.1],'Callback',{@NonRigid});
        uicontrol('Parent',hStageControl,'Style','pushbutton','String','Clear Warping','Units','normalized','Position',[0.51 0.19 0.47 0.1],'Callback',{@ClearWarping});    
        
        % Setup callbacks for mouse movements
        set(hWindow,'WindowScrollWheelFcn',{@transform});
        MouseStartPos = 0;
        PixelRatio = 1;
        
        % Setup initial transformation variables if necessary
        ss.SetupTransformParams(SiftParams);
        UpdateImage;
        ApplyTo = 'this';
        slist = CurrSlice;
        UndoHistory = [];
        RedoHistory = [];
 
        function ClearRedo()
            set(hRedo,'Enable','off');
            RedoHistory = [];
        end
        
        function UndoCheckpoint()
            set(hUndo,'Enable','on');
            if length(UndoHistory)>50
                UndoHistory(1) = [];
            end
            UndoHistory{end+1} = cell(ss.SliceNum,1);
            for i = 1:ss.SliceNum
                UndoHistory{end}{i} = copy(ss.Slices{i});
            end
        end
        
        function Undo(source,eventdata)
            if length(UndoHistory) > 0
                if length(RedoHistory) > 50
                    RedoHistory(1) = [];
                end
                RedoHistory{end+1} = cell(ss.SliceNum,1);
                for i = 1:ss.SliceNum
                    RedoHistory{end}{i} = copy(ss.Slices{i});
                end
                for i = 1:length(UndoHistory{end})
                    ss.Slices{i} = copy(UndoHistory{end}{i});
                end
                UndoHistory(end) = [];
                if isempty(UndoHistory)
                    set(hUndo,'Enable','off');
                end
                set(hRedo,'Enable','on');
                UpdateImage;
                set(hSliceNumSlider,'Value',CurrSlice/ss.SliceNum,'Min',1/ss.SliceNum,'Max',1,'SliderStep', [1/(ss.SliceNum-1) 1/(ss.SliceNum-1)]);
            end
        end
        
        function Redo(source,eventdata)
            if length(RedoHistory) > 0
                UndoHistory{end+1} = cell(ss.SliceNum,1);
                for i = 1:ss.SliceNum
                    UndoHistory{end}{i} = copy(ss.Slices{i});
                end
                for i = 1:length(RedoHistory{end})
                    ss.Slices{i} = copy(RedoHistory{end}{i});
                end
                RedoHistory(end) = [];
                if isempty(RedoHistory)
                    set(hRedo,'Enable','off');
                end
                set(hUndo,'Enable','on');
                UpdateImage;
                set(hSliceNumSlider,'Value',CurrSlice/ss.SliceNum,'Min',1/ss.SliceNum,'Max',1,'SliderStep', [1/(ss.SliceNum-1) 1/(ss.SliceNum-1)]);
            end
        end
        
        function SetSeed(varargin)
            ss.Seed = CurrSlice;
            set(hSeed,'String',['Reset Seed (' num2str(ss.Seed) ')']);
        end
        
        function NonRigid(source,eventdata)
            UndoCheckpoint;
            ss.SerialSiftFlow(SiftParams);
            UpdateImage;
            ClearRedo;
        end     
        
        function Rigid(source,eventdata)
            UndoCheckpoint;
            ss.SerialRigid(RigidOptimizer,RigidMetric);
            UpdateImage;
            ClearRedo;
        end
                    
        function ClearWarping(source,eventdata)
            UndoCheckpoint;
            for i = slist
                ss.Slices{i}.ClearWarp;
            end
            UpdateImage;
            ClearRedo;
        end
        
        function DeleteSlice(source,eventdata)
            UndoCheckpoint;
            if ss.SliceNum > 2 && strcmp('Yes',questdlg('Are you sure you want to delete this slice?'))
                ss.DeleteSlice(CurrSlice);
                if CurrSlice>ss.SliceNum
                    CurrSlice = ss.SliceNum;
                end
                if ss.Seed>ss.SliceNum
                    ss.Seed = ss.SliceNum;
                    set(hSeed,'String',['Reset Seed (' num2str(ss.Seed) ')']);
                end
                set(hSliceNumSlider,'Value',CurrSlice/ss.SliceNum,'Min',1/ss.SliceNum,'Max',1,'SliderStep', [1/(ss.SliceNum-1) 1/(ss.SliceNum-1)]);
                SliceChanged;
            end
            ClearRedo;
         end
        
        function transform(source,eventdata)
            switch source
                case hFlipH
                    UndoCheckpoint;
                    for i = slist
                        ss.Slices{i}.FlipH;
                    end
                case hFlipV
                    UndoCheckpoint;
                    for i = slist                    
                        ss.Slices{i}.FlipV;
                    end
                otherwise      % Scroll wheel
                    theta = eventdata.VerticalScrollCount;    
                    if theta ~= 0
                        for i = slist
                            ss.Slices{i}.Rotate(theta);
                        end
                    end
            end
            UpdateImage;
            ClearRedo;
        end
        
        function AutoRotateCenter(source,eventdata)
            UndoCheckpoint;
            hWait = waitbar(0,'Auto-rotating and centering..');
            set(hWait,'Name','Auto-Rotate and Center','WindowStyle','modal');
            for i = slist
                ss.Slices{i}.RotateAndCenter;
                waitbar(i/length(slist),hWait);
            end
            UpdateImage;
            delete(hWait);
            ClearRedo;
        end
        
        
        % Setup functions for handling mouse drags
        function StartDrag(source, eventdata)
            UndoCheckpoint;
            ClearRedo;
            % Define callback functions for when the cursor moves and when the
            % mouse botton is released
            set(hWindow,'WindowButtonMotionFcn',@Drag);
            set(hWindow,'WindowButtonUpFcn',@EndDrag);

            % Store cursor position when the mouse was clicked and the starting
            % position of the axis object
            MouseStartPos = get(hWindow,'CurrentPoint');
        end

        function Drag(source, eventdata)
            % Calculate new axis position
            CurrMousePos = get(hWindow,'CurrentPoint');
            hshift = (CurrMousePos(1)-MouseStartPos(1))*PixelRatio;
            vshift = -(CurrMousePos(2)-MouseStartPos(2))*PixelRatio;
            MouseStartPos = CurrMousePos;
            
            % Calculate new transformation matrix
            if (vshift ~= 0) || (hshift ~= 0)
                for i = slist
                    ss.Slices{i}.Shift(hshift,vshift);
                end
                UpdateImage;
            end
        end
        
        function EndDrag(source, eventdata)
            % Clear callback functions for mouse movement and button release
            set(hWindow,'WindowButtonMotionFcn','');
            set(hWindow,'WindowButtonUpFcn','');
        end
        
        function cleanup(source,eventdata)
            set(hWindow,'WindowScrollWheelFcn','');
        end
        
        function SliceChanged(varargin)
            CurrSlice = round(get(hSliceNumSlider,'Value')*ss.SliceNum);
            set(hSliceNumDisp,'String',num2str(CurrSlice));
            UpdateImage;
            switch ApplyTo
                case 'this'
                    slist = CurrSlice;
                case 'subsequent'
                    slist = CurrSlice:ss.SliceNum;
                case 'previous'
                    slist = 1:CurrSlice;
                case 'all'
                    slist = 1:ss.SliceNum;
            end
        end
        
        function ChangeApplyTo(source,eventdata)
            switch get(eventdata.NewValue,'String')
                case 'This slice only'
                    ApplyTo = 'this';
                    slist = CurrSlice;
                case 'All subsequent slices'
                    ApplyTo = 'subsequent';
                    slist = CurrSlice:ss.SliceNum;
                case'All previous slices'
                    ApplyTo = 'previous';
                    slist = 1:CurrSlice;
                case 'All slices'
                    ApplyTo = 'all';
                    slist = 1:ss.SliceNum;
            end
        end        
        
        function UpdateImage(varargin)
            
            % Get axis dimensions
            pos = getpixelposition(hAx);
            set(hAx,'XLim',[1 pos(3)],'YLim',[1 pos(4)]);
            
            % Get image and its dimensions
            
            if get(hShowPrev,'Value') && (CurrSlice ~= 1)
                % Create fusion of this image and previous image
                img = imfuse(ss.Slices{CurrSlice}.TransImg,ss.Slices{CurrSlice-1}.TransImg);
            else
                img = ss.Slices{CurrSlice}.TransImg;
            end
            w = size(img,2);
            h = size(img,1);

            if w/h > pos(3)/pos(4)
                margin = (pos(4)-pos(3)/w*h)/2;
                set(hImg,'CData',img,'XData',[1 pos(3)],'YData',[margin pos(4)-margin]);
                set(hAx,'Color','black');
                PixelRatio = w/pos(3);
            else
                margin = (pos(3)-pos(4)/h*w)/2;
                set(hImg,'CData',img,'XData',[margin pos(3)-margin],'YData',[1 pos(4)]);
                set(hAx,'Color','black');
                PixelRatio = h/pos(4);
            end
            
        end
    end

    %%
    function [ hStagePanel ] = BrainExport(hWindow,hStage,hNextStage,hPreviousStage )
        hMainPanel = uipanel('Parent',hWindow,'Units','normalized','Position',[0.015 0.02 0.62 0.96]);       % ,'DeleteFcn',{@cleanup});
        hStageControl = uipanel('Parent',hWindow,'Units','normalized','BorderType','none','Clipping','off','Position',[0.655 0.14 0.33 0.65]);      %'DeleteFcn',{@cleanup});
        hStagePanel = [hMainPanel hStageControl];
        
        % Export files to...
        hExportTo = uibuttongroup('Parent',hMainPanel,'Units','normalized','Position',[0.1 0.57 0.3 0.1],'Title','Export images to:','SelectionChangeFcn',{@ExportToChanged});
        hExportFile = uicontrol('Style','radiobutton','Parent',hExportTo,'Units','normalized','Position',[0.05 0.6 0.9 0.3],'String','File');
        hExportVar = uicontrol('Style','radiobutton','Parent',hExportTo,'Units','normalized','Position',[0.05 0.2 0.9 0.3],'String','Workspace');
        
        % Organize files ...
        hOrg = uibuttongroup('Parent',hMainPanel,'Units','normalized','Position',[0.1 0.43 0.3 0.13],'Title','Export to separate files/variables:');
        uicontrol('Style','radiobutton','Parent',hOrg,'Units','normalized','Position',[0.05 0.74 0.9 0.3],'String','Channels');
        uicontrol('Style','radiobutton','Parent',hOrg,'Units','normalized','Position',[0.05 0.42 0.9 0.3],'String','Slices');
        uicontrol('Style','radiobutton','Parent',hOrg,'Units','normalized','Position',[0.05 0.10 0.9 0.3],'String','Channels and slices');
        
        % Channel selection
        chlist = ss.BrainImagesObj.ChannelList;
        for i = 1:length(chlist)
            ch{i}{1} = chlist{i};
        end
        hChannels = uicontrol('Style','listbox','Parent',hMainPanel,'Units','normalized','Position',[0.42 0.49 0.25 0.18],'String',chlist,'Max',3,'Min',1);
        hMergeCh = uicontrol('Style','pushbutton','Parent',hMainPanel,'Units','normalized','String','Merge Channels','Position',[0.42 0.43 0.12 0.05],'Callback',{@MergeChannels});
        hSplitCh = uicontrol('Style','pushbutton','Parent',hMainPanel,'Units','normalized','String','Split Channels','Position',[0.55 0.43 0.12 0.05],'Callback',{@SplitChannels});
        
        % Export button
        hExport = uicontrol('Style','pushbutton','Parent',hMainPanel,'Units','normalized','String','Export','Position',[0.69 0.43 0.215 0.07],'Enable','off','Callback',{@Export});
        
        % Save location controls
        hFileSave = uicontrol('Style','pushbutton','Parent',hMainPanel,'Units','normalized','String','Select Export File','Position',[0.69 0.51 0.215 0.05],'Callback',{@SelectFile});
        uicontrol('Style','text','Parent',hMainPanel,'String','Save to variable:','HorizontalAlignment','left','Units','normalized','Position',[0.69 0.58 0.12 0.02]);
        hSaveToVar = uicontrol('Style','edit','Parent',hMainPanel,'String','','BackgroundColor','white','Units','normalized','Position',[0.805 0.57 0.1 0.04],'Callback',{@SaveVarChanged});
        
        % Downsample controls
        uicontrol('Style','text','Parent',hMainPanel,'String','Downsampling:','HorizontalAlignment','left','Units','normalized','Position',[0.69 0.63 0.12 0.02]);
        hDownsample = uicontrol('Style','edit','Parent',hMainPanel,'String',num2str(4),'BackgroundColor','white','Units','normalized','Position',[0.805 0.62 0.05 0.04],'Callback',{@DownsampleChanged});
        
        ExportFile = '';
        ExportTo = 'File';
        SaveToVar = '';
        FinalDs = 4;
        ss.SetupTransformParams(SiftParams);        % In case this wasn't done previously
        
        function DownsampleChanged(source,eventdata)
            NewDs = str2num(get(hDownsample,'String'));
            if ~isempty(NewDs)
                if floor(log2(NewDs))==log2(NewDs)
                    % Check that it's a power of 2
                    FinalDs = NewDs;
                else
                    msgbox('Downsampling rate must be a power of 2.','Error','error');
                    set(hDownsample,'String',num2str(FinalDs));
                end
            else
                set(hDownsample,'String',num2str(FinalDs));
            end
        end
        
        function ExportToChanged(source,eventdata)
            ExportTo = get(eventdata.NewValue,'String');
            if strcmp('File',ExportTo) && ~isempty(ExportFile)
                set(hExport,'Enable','on');
            elseif strcmp('Workspace',ExportTo) && ~isempty(SaveToVar)
                set(hExport,'Enable','on');
            else
                set(hExport,'Enable','off');
            end
        end
        
        function SaveVarChanged(source,eventdata)
            NewName = get(hSaveToVar,'String');
            if isvarname(NewName)
                SaveToVar = NewName;
                set(hExportTo,'SelectedObject',hExportVar);
                set(hExport,'Enable','on');
                ExportTo = 'Workspace';
            else
                if ~isempty(NewName)
                    set(hSaveToVar,'String',SaveToVar);
                    msgbox([NewName ' is not a valid MATLAB variable name'],'Error','error');
                end
            end
            
        end
        
        function SelectFile(source,eventdata)
            [ExportFile,FilePath,~] = uiputfile({'*.tif' '3D Brain TIF File'});
            if ischar(ExportFile)
                [~,ExportFile,~] = fileparts(ExportFile);
                ExportFile = [FilePath ExportFile];
                ExportTo = 'File';
                set(hExport,'Enable','on');
                set(hExportTo,'SelectedObject',hExportFile);
            else
                ExportFile = '';
            end
        end
            
        
        function MergeChannels(source,eventdata)
            sel = get(hChannels,'Value');
            if length(sel) > 1
                for i = length(sel):-1:2
                    ch{sel(1)}{end+1:end+length(ch{sel(i)})} = ch{sel(i)}{:};
                    ch(sel(i)) = [];
                    chlist{sel(1)} = [chlist{sel(1)} '/' chlist{sel(i)}];
                    chlist(sel(i)) = [];
                end
                set(hChannels,'Value',sel(1),'String',chlist);

            end
            %assignin('base','q',ch);
        end
        
        function SplitChannels(source,eventdata)
            sel = get(hChannels,'Value');
            if length(sel)==1 && length(ch{sel})>1
                for i = 2:length(ch{sel})
                    ch{end+1}{1} = ch{sel}{i};
                    chlist{end+1} = ch{end}{1};
                end
                chlist{sel} = ch{sel}{1};
                ch{sel}(2:end) = [];
                set(hChannels,'String',chlist);
            end
            assignin('base','q',ch);
        end
        
        function Export(source,eventdata)
            % Get export parameters
            org = get(get(hOrg,'SelectedObject'),'String');
            CurrDs = ss.BrainImagesObj.Downsample;
            scale = CurrDs/FinalDs;
            
            % Get which channel(s) to export
            sel = get(hChannels,'Value');
            ExportCh = ch(sel);
            chnames = chlist(sel);
            for i = 1:length(chnames)
                chnames{i} = strrep(chnames{i},'/','');
                chnames{i} = strrep(chnames{i},' ','');
            end
            
             % Check if the files that will be written to already exist, and
            % delete them if they do
            FileList = [];
            if strcmp(ExportTo,'File')
                for i = 1:ss.SliceNum
                    for j = 1:length(chnames)
                        switch org
                            case 'Channels'
                                fout = [ExportFile '_c' chnames{j} '.tif'];
                            case 'Slices'
                                fout = [ExportFile '_s' num2str(i) '.tif'];
                            case 'Channels and slices'
                                fout = [ExportFile '_s' num2str(i) '_' chnames{j} '.tif'];
                        end
                        if ~any(strcmp(FileList,fout)) && exist(fout,'file')
                            FileList{end+1} = fout;
                        end 
                    end
                end
            end
            if ~isempty(FileList)
                if length(FileList)>10
                    ans = questdlg(['The following files will be overwritten:' {FileList{1:5} '.' '.' '.' FileList{end-4:end}} 'Are you sure you want to continue?']);
                else
                    ans = questdlg(['The following files will be overwritten:' FileList 'Are you sure you want to continue?']);
                end
                if strcmp(ans,'Yes')
                    for i = 1:length(FileList)
                        delete(FileList{i});
                    end
                else
                    return;
                end
            end
            
            % Calculate parameters necessary for sift warping
            patchsize = ss.Slices{1}.Width-size(ss.Slices{1}.Transform.vx,2)+2;
            trim = (patchsize/2-1)*scale;       % trim for warping
            
            % Create waitbar
            hWait = waitbar(0,'Exporting Images','CreateCancelBtn',{@ExportCancel});
            %set(hWait,'Name','Exporting Images','WindowStyle','modal');
            canceled = 0;
            proctime = tic;
            
            % Loop through slices
            for i = 1:ss.SliceNum
                if canceled
                        break
                end
                
                % Update waitbar
                if i==1
                    waitbar(i/ss.SliceNum,hWait);
                    set(hWait,'Name',['Exporting slice ' num2str(i) ' of ' num2str(ss.SliceNum)]);
                else
                    waitbar(i/ss.SliceNum,hWait,sprintf(['Estimated time remaining: ' num2str(datestr(toc(proctime)/(i-1)*(ss.SliceNum-i+1)/86400,'HH:MM:SS'))]));
                    set(hWait,'Name',['Exporting slice ' num2str(i) ' of ' num2str(ss.SliceNum)]);
                end
                
                % Scale transformations
                affine = ss.Slices{i}.Transform.Affine;
                affine(3,1:2) = affine(3,1:2)*scale;
                affine2 = ss.Slices{i}.Transform.Affine2;
                affine2(3,1:2) = affine2(3,1:2)*scale;
                affine = maketform('affine',affine);
                affine2 = maketform('affine',affine2);
                if sum(sum(ss.Slices{i}.Transform.vx)) ~= 0 || sum(sum(ss.Slices{i}.Transform.vy)) ~= 0
                    vx = imresize(ss.Slices{i}.Transform.vx*scale,scale,'bicubic');
                    vy = imresize(ss.Slices{i}.Transform.vy*scale,scale,'bicubic');
                else
                    vx = [];
                    vy = [];
                end
                wout = ss.Slices{1}.Width*scale;
                hout = ss.Slices{1}.Height*scale;
                
                % Get image mask
                if ~ss.Slices{i}.CleanParams.ManualMask
                    % Re-generate mask for the full resolution image
                    % Load the channel used for making the mask
                    img = ss.ReadImage(i,FinalDs,'import');
                    img(1,1) = 0;
                    img(1,2) = 255;
                    mask = im2bw(img/255, ss.Slices{i}.CleanParams.MaskThreshold/255);
                    mask = imfill(mask,'holes');
                    mask = bwareaopen(mask,round(ss.Slices{i}.CleanParams.MinSize*scale^2));
                else
                    mask = imresize(ss.Slices{i}.Mask,scale,'bicubic');
                end

                % Loop through the channels
                for j = 1:length(ExportCh)
                    
                    if canceled
                        break
                    end
                    
                    % Read in image for this channel
                    img = [];
                    for k = 1:length(ExportCh{j})
                        try
                            img(:,:,k) = ss.ReadImage(i,FinalDs,ExportCh{j}{k});
                        end
                    end
                    if isempty(img)
                        img = zeros(2,2,1);
                    end
                    img = max(img,[],3);        % Maximum intensity projection of merged channels

                    % Adjust mask size (in case of manual mask, after
                    % resizing, size may differ by a pixel)
                    if size(mask,1)<size(img,1)
                        mask(size(img,1),1)=0;
                    elseif size(mask,1)>size(img,1)
                        mask = mask(1:size(img,1),1:end);
                    end
                    if size(mask,2)<size(img,2)
                        mask(1,size(img,2))=0;
                    elseif size(mask,2)>size(img,2)
                        mask = mask(1:end,1:size(img,2));
                    end
                    
                    % Apply mask
                    img = img.*mask;

                    % Transform
                    img = imtransform(img,affine,'UData',[-size(img,2)/2 size(img,2)/2],'VData',[-size(img,1)/2 size(img,1)/2],'XData',[-floor(wout/2) floor(wout/2)],'YData',[-floor(hout/2) floor(hout/2)],'XYScale',1);
                    if ~isempty(vx)
                        imwarp = zeros(hout,wout);
                        imwarp(trim+1:end-trim,trim+1:end-trim,:) = warpImage(img(trim+1:end-trim,trim+1:end-trim,:),vx,vy);
                        img = imwarp;
                        imwarp = [];
                    end
                    if ~isequal(affine2,[1 0 0; 0 1 0; 0 0 1])
                        img = imtransform(img,affine2,'UData',[-wout/2 wout/2],'VData',[-hout/2 hout/2],'XData',[-floor(wout/2) floor(wout/2)],'YData',[-floor(hout/2) floor(hout/2)],'XYScale',1);
                    end
                    
                    % Write to file
                    if strcmp(ExportTo,'File')
                        switch org
                            case 'Channels'
                                fout = [ExportFile '_c' chnames{j} '.tif'];
                            case 'Slices'
                                fout = [ExportFile '_s' num2str(i) '.tif'];
                            case 'Channels and slices'
                                fout = [ExportFile '_s' num2str(i) '_' chnames{j} '.tif'];
                        end
                        
                        % Write file
                        success = 0;
                        writetime = tic;
                        while success==0
                            if toc(writetime)<30
                                try
                                    imwrite(img,gray,fout,'WriteMode','append');
                                    success = 1;
                                end
                            else
                                if strcmp('Yes',questdlg('File write operation timed out. Would you like to continue trying? If you answer ''No,'' then exporting will stop.'))
                                    writetime = tic;
                                else
                                    delete(hWait);
                                    return;
                                end
                            end
                        end
                        
                    else
                        switch org
                            case 'Channels'
                                fout = [SaveToVar '_c' chnames{j}];
                            case 'Slices'
                                fout = [SaveToVar '_s' num2str(i)];
                            case 'Channels and slices'
                                fout = [SaveToVar '_s' num2str(i) '_' chnames{j}];
                        end
                        % Create variable if it doesn't already exist
                        if ~evalin('base',['exist(''' fout ''',''var'');'])
                            assignin('base',fout,zeros(0,0,0));
                        end
                        assignin('base','imgtemp',img);
                        evalin('base',[fout '(:,:,end+1)=imgtemp;']);
                        evalin('base','imgtemp=[];');
                    end
                end
         
             end
            
            delete(hWait);
            
            function ExportCancel(source,eventdata)
                canceled = 1;
            end
        end
        
    end


end


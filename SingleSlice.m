classdef SingleSlice < matlab.mixin.Copyable
    
    properties
        Position
        FileGroupID
        Order
        Handle
        Image
        ImgIndex
        OrderAxPos
        HandleB
        CleanParams
        Mask
        ProcImg
        Transform
        TransImg
        Width               % Width and height are for the transformed image
        Height
    end
     
    properties (Dependent = true, SetAccess = private)
        OrderAxCenter
        OriginShift
        ReturnOrigin     
    end
    
    properties (Constant)
    end
    
    methods
        function slice = SingleSlice(Position,FileGroupID)
            slice.Position = Position;
            slice.FileGroupID = FileGroupID;
            slice.ImgIndex = 1;
            CleanParams.MaskThreshold = 0;
            CleanParams.ManualMask = 0;
            CleanParams.MinSize = 1;
            CleanParams.AutoContrast = 1;
            CleanParams.ContrastMin = [];
            CleanParams.ContrastMax = [];
            CleanParams.ContrastGamma = [];
            slice.CleanParams = CleanParams;      
        end  
        
        
        function img = get.TransImg(slice)
            % Calculate patchsize
            patchsize = slice.Width-size(slice.Transform.vx,2)+2;
            tform = maketform('affine',slice.Transform.Affine);
            w = size(slice.ProcImg,2);
            h = size(slice.ProcImg,1);
            img = imtransform(slice.ProcImg,tform,'UData',[-w/2 w/2],'VData',[-h/2 h/2],'XData',[-floor(slice.Width/2) floor(slice.Width/2)],'YData',[-floor(slice.Height/2) floor(slice.Height/2)],'XYScale',1);
            imgcopy=img(patchsize/2:end-patchsize/2+1,patchsize/2:end-patchsize/2+1,:);
            img=zeros(size(img));
            img(patchsize/2:end-patchsize/2+1,patchsize/2:end-patchsize/2+1,:)=warpImage(imgcopy,slice.Transform.vx,slice.Transform.vy);
            if ~isequal([1 0 0; 0 1 0; 0 0 1],slice.Transform.Affine2)
                tform = maketform('affine',slice.Transform.Affine2);
                img = imtransform(img,tform,'UData',[-slice.Width/2 slice.Width/2],'VData',[-slice.Height/2 slice.Height/2],'XData',[-floor(slice.Width/2) floor(slice.Width/2)],'YData',[-floor(slice.Height/2) floor(slice.Height/2)],'XYScale',1);
            end
        end
  
        
        function RotateAndCenter(slice)
            tform = maketform('affine',slice.Transform.Affine);
            w = size(slice.Mask,2);
            h = size(slice.Mask,1);
            % Get transformed maask, sampling much larger area of output
            % space in case the user dragged the image outside the center
            % region and wants to bring it back to the center
            mask = uint8(imtransform(slice.Mask,tform,'UData',[-w/2 w/2],'VData',[-h/2 h/2],'XData',[-slice.Width*4 slice.Width*4],'YData',[-slice.Height*4 slice.Height*4],'XYScale',1));
            % Merge all components
            p = bwconncomp(mask);
            for i = 1:length(p.PixelIdxList)
                mask(p.PixelIdxList{i}) = 1;     % 2 makes it a label matrix
            end
            mask(1) = 2;                        % Makes it a label matrix  
            p = regionprops(mask,'Area','Centroid','Orientation');% 
            if length(p)>0
                [~,largest] = max([p.Area]);
                % Calculate the necessary shift
                ximg = slice.Width*4;
                yimg = slice.Height*4;
                hshift = ximg-p(largest).Centroid(1);
                vshift = yimg-p(largest).Centroid(2);
                slice.Shift(hshift,vshift);
                slice.Rotate(-p(largest).Orientation);
            end
        end
        
        function Rigid(slice, fixed, optimizer, metric)
            % Register slice to fixed image using optimizer and metric
            % settings
            if verLessThan('matlab', '8.1')
                [~, tformObj] = imregisterB(slice.TransImg,fixed,'rigid',optimizer,metric);
            else
            	tformObj = imregtform(slice.TransImg,fixed,'rigid',optimizer,metric);
            end
             
             % First matrix shifts image so that the upper left hand corner
             % is at the origin, second is the registration transformation,
             % and the third shifts the regisetered image back so that it's
             % center's at the origin
             slice.ApplyTransform([1 0 0; 0 1 0; slice.Width/2 slice.Height/2 1]*tformObj.tdata.T*[1 0 0; 0 1 0; -slice.Width/2 -slice.Height/2 1]);
        end
        
        function SiftFlow(slice, fixed, SiftParams)
            Sift1=dense_sift(fixed,SiftParams.patchsize,SiftParams.gridspacing);
            Sift2=dense_sift(slice.TransImg,SiftParams.patchsize,SiftParams.gridspacing);
            [slice.Transform.vx,slice.Transform.vy,~]=SIFTflowc2f(Sift1,Sift2,SiftParams);
        end
        
        function Shift(slice, hshift, vshift)
            slice.ApplyTransform([1 0 0; 0 1 0; hshift vshift 1]);
        end
        
        function Rotate(slice, theta)
            slice.ApplyTransform([cosd(theta) -sind(theta) 0; sind(theta) cosd(theta) 0; 0 0 1]);
        end
        
        function FlipH(slice)
            slice.ApplyTransform([-1 0 0; 0 1 0; 0 0 1]);
        end
        
        function FlipV(slice)
            slice.ApplyTransform([1 0 0; 0 -1 0; 0 0 1]); 
        end
        
        function ApplyTransform(slice,t)
            if sum(sum(slice.Transform.vx))== 0 && sum(sum(slice.Transform.vy))==0
                % Apply to pre-warp transform
                slice.Transform.Affine = slice.Transform.Affine*t;
            else
                % Apply to post-warp transform
                slice.Transform.Affine2 = slice.Transform.Affine2*t;
            end
        end
        
        function ClearWarp(slice)
            slice.Transform.Affine = slice.Transform.Affine*slice.Transform.Affine2;
            slice.Transform.Affine2 = [1 0 0; 0 1 0; 0 0 1];
            slice.Transform.vx(:,:) = 0;
            slice.Transform.vy(:,:) = 0;
        end
        
        function slice = set.CleanParams(slice,CleanParams)
            slice.CleanParams = CleanParams;
           % slice = slice.ProcessImage;
        end
        
        function ProcessImage(slice)
             if ~slice.CleanParams.ManualMask && ~isempty(slice.Image)      %~isempty(slice.CleanParams.MaskThreshold) && ~isempty(slice.CleanParams.MinSize) && 
                % Ensure that full 0-255 range is represented in img for im2bw
                img = slice.Image;
                img(1,1) = 0;
                img(1,2) = 255;

                % Create binary image based on threshold from 0 to 255
                slice.Mask = im2bw(img/255, slice.CleanParams.MaskThreshold/255);

                % Fill holes in thresholded image
                slice.Mask = imfill(slice.Mask,'holes');

                % Remove all objects from the binary image with areas smaller than
                % MinSize pixels
                slice.Mask = bwareaopen(slice.Mask,slice.CleanParams.MinSize);
                
                % Apply mask to processed image
                slice.ProcImg = slice.Mask.*slice.Image;
             elseif slice.CleanParams.ManualMask && ~isempty(slice.Image)
                % Apply mask to processed image
                slice.ProcImg = slice.Mask.*slice.Image;
             elseif ~isempty(slice.Image);
                slice.ProcImg = slice.Image;
             end
            
            if ~isempty(slice.ProcImg)
                % Set autocontrast limits
                if slice.CleanParams.AutoContrast
                    %highlow = stretchlim(slice.ProcImg/255);
                    highlow = stretchlim(slice.Image(slice.Mask)/255);          % Only consider pixel values not excluded by the mask
                    slice.CleanParams.ContrastMin = highlow(1)*255;
                    slice.CleanParams.ContrastMax = highlow(2)*255;
                    slice.CleanParams.ContrastGamma = 1;
                end

                % Adjust contrast
                if ~isempty(slice.CleanParams.ContrastMin) && ~isempty(slice.CleanParams.ContrastMax) && ~isempty(slice.CleanParams.ContrastGamma)
                    slice.ProcImg = imadjust(slice.ProcImg/255, [slice.CleanParams.ContrastMin/255; slice.CleanParams.ContrastMax/255], [0; 1], slice.CleanParams.ContrastGamma)*255;
                end
            end
        end
        
        
        function slice = set.Image(slice,Image)
            slice.Image = Image;
            slice.ProcessImage;
        end
        
        function OrderAxCenter = get.OrderAxCenter(slice)
            OrderAxCenter = [slice.OrderAxPos(1)+slice.OrderAxPos(3)/2 slice.OrderAxPos(2)+slice.OrderAxPos(4)/2];
        end
        
        
    end
    
end


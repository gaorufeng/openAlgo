%% Moving Average with Profit Taking Sweep
%
%	This script runs a parametric sweep using a moving average signal generator coupled
%	with a number of ticks profit taker.
%	Signal 1:	Moving Average crossover
%
%	The signal is generated and then passed to the profit taking routine.
%
%	This pair can then be passed into a genetic algorithm to see how the results would differ
%	with various mutations
%

%% Parameter sweep settings
% Set cluster
%	0  -  none
%	1  -  6		local
%	>  6		Core

clust = 4;

%% Initialize variables
%%%%%%%%%%%%%%%%%%%%%%%%%
%	Variables	%
%%%%%%%%%%%%%%%%%%%%%%%%%
% Create a range variable so we can vectorize inputs for parametric sweep

% MOVING AVERAGE
optEnd = 35;
%leadStart = 1; leadEnd = optEnd; lagStart = 1; lagEnd = optEnd*2;
leadStart = 1; leadEnd = optEnd; lagStart = 1; lagEnd = 75;

fastMA = leadStart:leadEnd; slowMA = lagStart:lagEnd; typeMA=0;

% PROFIT TAKER
%%%%%%%% [barsOut,sigOut,sharpeOut] = numTicksProfit(barsIn,sigIn,sharpeIn,minTick,numTicks,openAvg)
numTicks = 2:10; openAvg = 0;

%% Select datafile and time adjustment(s)
%	KC1D  (KC)	Arabica Futures	Daily	all years
%	KC1D5 (KC)	Arabica Futures	Daily	5 years
%	KC1M  (KC)	Arabica Futures	1 min	1 year
%	KC5S  (KC)	Arabica Futures	5 sec	6 mos
%	KC5SV (KC)	Arabica Futures	5 sec	6 mos	Validation Set
%	ES5S  (ES)	E-Mini S&P	5 sec	6 mos
%	ES5SV (ES)	E-Mini S&P	5 sec	6 mos	Validation Set
%	ES1M  (ES)	E-Mini S&P	1 min	all years
%	ES1M1 (ES)	E-Mini S&P	1 min	1 year
%	ES1M3 (ES)	E-Mini S&P	1 min	3 year
%
%  	Variable to create virtual bars.  Use for small period data series
%	5 second conversions:	1 min = 12,	2 min = 24,	3 min = 36,	4 min = 48,	
%				5 min = 60,	50 secs = 10,	45 secs = 9,	40 secs = 8,	
%				30 secs = 6,	20 secs = 4,	15 secs = 3,	10 secs = 2
contract = 'ES1M1';
contractA = 'KC5S';
contractB = 'KC5SV';

if (strcmp(contractA,contractB))
	error('Price inputs identical...aborting');
end %if

% Enter either [time] or [startTime endTime]
%time = [2 3 4 6 8 9 10 12 24 36 48 60];			%#ok<NBRAK>
time = [36 48 60]; 
%% Load Data
[dFileA, defFile, scaling] = dataSelect(contractA);
[dFileB, ~, ~] = dataSelect(contractB);
dataA = importFromTxt(dFileA);
dataB = importFromTxt(dFileB);
importSymbolDef(defFile);

%%  Cost basis
%%%%%%%%%%%%%%%%%%%%%%%%%%%
%   Commissions & Fees    %
%%%%%%%%%%%%%%%%%%%%%%%%%%%
%
cost=5; % $5 Round turn commission

%% Confirm cluster is active
% Ensure cluster is set to correct config
if matlabpool('size') ~= clust
	warning('Cluster being configured or closed as needed.  Adjusting...');
    
	if matlabpool('size') ~= 0
		matlabpool CLOSE;
	end;
    
	if clust > 1 && clust < 7
		matlabpool('local',clust);
	else
		matlabpool('Core',clust);
	end; %if

end; %if

%%	Initialize variables
%%%%%%%%%%%%%%%%%%%%%%%%%%%
%        Variables        %
%%%%%%%%%%%%%%%%%%%%%%%%%%%
%

% Create a range variable so we can vectorize inputs for parametric sweep
range = {fastMA, slowMA, typeMA, numTicks, openAvg};

%% Perform the parameter sweep

fprintf('\n\n *** BEGIN PARAMETRIC SWEEP ***\n');
disp('.....................');
startTime = datestr(now);
disp(startTime);
disp('.....................');

%% Annual scaling reset value
inScaling = scaling;

%% Variable to create virtual bars.  Use for small period data series
% parse 'time' variable
if numel(time) == 1
	tStart = time;
	tEnd = time;
elseif numel(time) == 2
	tStart = time(1);
	tEnd = time(2);
else
	error('Unable to parse ''time'' variable.  Aborting...');
end; %if

%% Iterate over time 
%for t=tStart:tEnd
for t = time
    
	% Using a variable for parametric sweep range end so that we can automatically extend it if the
	% optimization finds the boundary value to be the best fit.
    
	% Reinitialize start time
	startTime = datestr(now);
    
	fprintf('Now processing vBar of %d\n',t);
	if t==1
		vBarsA = dataA;
		vBarsB = dataB;
	else
		vBarsA = virtualBars_mex(dataA,t); 
		vBarsB = virtualBars_mex(dataB,t); 
		scaling = inScaling / t;
	end %if
    
	%% Break up vBars into 80% test and 20% validation sets
	% testPts = floor(0.8*length(vBars));
	% vBarsTest = vBars(1:testPts,:);
	% vBarsVal = vBars(testPts+1:end,:);
    
	%% Define parallel function for parametric sweep
	% Ordinarily we would pass a Test set then review a Validation set
	% The parallel function marsiPARMETS sweeps for the best METSharpe and need the full data set.
	% METSharpe is a weighted version of the classic sharpe ratio that looks at both a Test data set result
	% and a validation set result and scores them with their weighted average.
	% Because of this we will not pass a vBarsTest, but will pass the entire data set.
	fun = @(x) ma2inputsNumTicksPft2vBarsPARMETS(x,vBarsA,vBarsB,minTick,bigPoint,cost,scaling);
    
	%% Sweep for best METSharpe
	%%%%%%%%%%%%%%%%%%%%%%%%%%%
	%          SWEEP          %
	%%%%%%%%%%%%%%%%%%%%%%%%%%%
	% Provide a bit of feedback for the user
	optInfo(1, range);
	tic
		%[maxSharpe,param,sh] = parameterSweep(fun,range);
		[maxSharpe,param] = parameterSweep(fun,range);
	toc
    
	% Extend the optimization range if we detect a maximum on the moving average lag boundary
	if param(2) == lagEnd
		curEnd = lagEnd;
		while param(2) == curEnd
			curEnd=curEnd+5;
			range = {leadStart:curEnd,curEnd-5:curEnd, typeMA, numTicks, openAvg};          
			fprintf('Found optimized value at iteration''s Moving Average Lag boundary.');
			fprintf(' Increasing range. %s\n',datestr(now));
			fprintf('Range extended to: \n')
			for ii = 1:length(range)
				formatSpec = '          Parameter %d: %s\n';
				fprintf(formatSpec,ii,vect2colon(range{ii}));
			end;
			[maxSharpe,param] = parameterSweep(fun,range);
	toc
		end;
	range = {leadStart:curEnd,lagStart:curEnd, typeMA, numTicks, openAvg};
	end;
    
	endTime = datestr(now);
    
	%% Disply results to command window
	fprintf('Optimization completed: ');
	fprintf(endTime);
	fprintf('\n\nParametric sweep found the following optimized values sweeping for METSharpe: \n');
	fprintf('     Bars In Test Set: %s\n',thousandSep(length(vBarsA)));
	formatSpec = '     Lead: %d          Lag: %d               MA type: %d\n     # Ticks: %d     Liq Strategy: %d\n\n';
	fprintf(formatSpec,param(1),param(2),param(3),param(4),param(5));
    
	[~,rMA,shMA]=ma2inputsSIG_mex(vBarsA,param(1),param(2),param(3),bigPoint,cost,scaling);
	fprintf('MA Sharpe Ratio = %s\n',num2str(shMA,3));
	fprintf('Cumulative Return = %s\n\n',thousandSepCash(sum(rMA)));
    
	[~,~,rMaPft,shMaPft]=ma2inputsNumTicksPftSIG_mex(vBarsA,param(1),param(2),param(3),...
	minTick,param(4),param(5),...
	bigPoint,cost,scaling);
	fprintf('MA w/ Profit Sharpe Ratio = %s\n',num2str(shMaPft,3));
	fprintf('Cumulative Return = %s\n\n',thousandSepCash(sum(rMaPft)));
    
	ma2inputsNumTicksPftSIG_DIS(vBarsA,param(1),param(2),param(3),...
	minTick,param(4),param(5),...
	bigPoint,cost,scaling);
	titleOne = ['Parametric Result - Entire Data One - vBars: ' num2str(t)];
	set(gcf,'name',titleOne)
	%snapnow;
    
	ma2inputsNumTicksPftSIG_DIS(vBarsB,param(1),param(2),param(3),...
		minTick,param(4),param(5),...
		bigPoint,cost,scaling);
	titleTwo = ['Parametric Result - Entire Data Two - vBars: ' num2str(t)];
	set(gcf,'name',titleTwo)
	snapnow;
    
	fprintf('\n                    -- Iteration Complete --\n\n\n');
    
	%% Export optimization into simple text file
	disp('Now exporting current run into text file log');
	if ~exist('\\SHARE\Matlab\OutputLogs\ma2iNumTicksPft2vBars Parametric Sweep Results.txt','file')
		fid = fopen('\\SHARE\Matlab\OutputLogs\ma2iNumTicksPft2vBars Parametric Sweep Results.txt','w');
	else
		fid = fopen('\\SHARE\Matlab\OutputLogs\ma2iNumTicksPft2vBars Parametric Sweep Results.txt','a');
	end; %if
    
	% Get the number of iterations we processed
	strNumI = thousandSep(numIterations(range));
    
	fprintf(fid,'\r\n\r\n*** BEGIN PARAMETRIC SWEEP ***\r\n');
	fprintf(fid,'Data file one: %s\r\n',dFileA);
	fprintf(fid,'Data file two: %s\r\n',dFileB);
	fprintf(fid,'Start Time %s\r\n',startTime);
	fprintf(fid,'\r\nNow processing vBar of %d\r\n',t);
	formatSpec = '\r\nOptimization range(s):\r\n';
	fprintf(fid,formatSpec);
	for ii = 1:length(range)
		if isempty(range{ii})
			formatSpec = '          Parameter %d: Not Given\r\n';
			fprintf(formatSpec,ii)
		else
			formatSpec = '          Parameter %d: %s\r\n';
			fprintf(fid,formatSpec,ii,vect2colon(range{ii}));
		end;
	end;
    
	formatSpec = '\r\nNumber of iterations performed: %s\r\n\r\n';
	fprintf(fid,formatSpec,strNumI);
    
	fprintf(fid,'\r\nParametric sweep found the following optimized values sweeping for METSharpe: \r\n');
	fprintf(fid,'     Bars In Test Set: %s\r\n',thousandSep(length(vBarsA)));
	formatSpec = '     Lead: %d          Lag: %d               MA type: %d\n     # Ticks: %d     Liq Strategy: %d\n\n';
	fprintf(fid,formatSpec,param(1),param(2),param(3),param(4),param(5));
    
	fprintf(fid,'MA Sharpe Ratio = %s\r\n',num2str(shMA,3));
	fprintf(fid,'Cumulative Return = %s\r\n\r\n',thousandSepCash(sum(rMA)));
	fprintf(fid,'MA w/ NumTicksPfr Sharpe Ratio = %s\r\n',num2str(shMaPft,3));
	fprintf(fid,'Cumulative Return = %s\r\n\r\n',thousandSepCash(sum(rMaPft)));
    
	fprintf(fid,'End Time %s\r\n',endTime);
	fprintf(fid,'*** END PARAMETRIC SWEEP ***\r\n');
	fclose(fid);
	fprintf(' **** JOB COMPLETE ****\n');
end; %for

%% END SCRIPT

%
%  -------------------------------------------------------------------------
%
%	 ██████╗ ██████╗ ███████╗███╗   ██╗ █████╗ ██╗      ██████╗  ██████╗ 
%	██╔═══██╗██╔══██╗██╔════╝████╗  ██║██╔══██╗██║     ██╔════╝ ██╔═══██╗
%	██║   ██║██████╔╝█████╗  ██╔██╗ ██║███████║██║     ██║  ███╗██║   ██║
%	██║   ██║██╔═══╝ ██╔══╝  ██║╚██╗██║██╔══██║██║     ██║   ██║██║   ██║
%	╚██████╔╝██║     ███████╗██║ ╚████║██║  ██║███████╗╚██████╔╝╚██████╔╝
%	 ╚═════╝ ╚═╝     ╚══════╝╚═╝  ╚═══╝╚═╝  ╚═╝╚══════╝ ╚═════╝  ╚═════╝
%   
%  -------------------------------------------------------------------------
%        This code is distributed in the hope that it will be useful,
%
%                      	 WITHOUT ANY WARRANTY
%
%                  WITHOUT CLAIM AS TO MERCHANTABILITY
%
%                  OR FITNESS FOR A PARTICULAR PURPOSE
%
%                           expressed or implied.
%
%   Use of this code, pseudocode, algorithmic or trading logic contained
%   herein, whether sound or faulty for any purpose is the sole
%   responsibility of the USER. Any such use of these algorithms, coding
%   logic or concepts in whole or in part carry no covenant of correctness
%   or recommended usage from the AUTHOR or any of the possible
%   contributors listed or unlisted, known or unknown.
%
%   Any reference of this code or to this code including any variants from
%   this code, or any other credits due this AUTHOR from this code shall be
%   clearly and unambiguously cited and evident during any use, whether in
%   whole or in part.
%
%   The public sharing of this code does not relinquish, reduce, restrict or
%   encumber any rights the AUTHOR has in respect to claims of intellectual
%   property.
%
%   IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE FOR ANY
%   DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
%   DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
%   OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
%   HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT,
%   STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN
%   ANY WAY OUT OF THE USE OF THIS SOFTWARE, CODE, OR CODE FRAGMENT(S), EVEN
%   IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
%
%   -------------------------------------------------------------------------
%
%                             ALL RIGHTS RESERVED
%
%   -------------------------------------------------------------------------
%
%   Author:	Mark Tompkins
%   Revision:	
%   Copyright:	(c)2015

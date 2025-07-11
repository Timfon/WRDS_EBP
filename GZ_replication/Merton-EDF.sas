/* This program uses the methodology of Bharath and Shumway (RFS, 2008)
   to calculate the monthly distance to default (DD) and EDF using the
   KMV-Merton model of default.
   NOTE:
   (1) This program calculates the DD for one month only and is embedded
       in the LOOP-MERTON-EDF.sas program.
   ARGUMENTS:
   YYYY.................year (4-digits). 
   MM...................month (2-digits).
   OUTDS................name of the output data.
   CRSPDS...............name of the data set containing the following
                        variables from the daily CRSP input data set:
                        PERMCO = cross-sectional (i.e., firm) identifier
                        DATE = SAS date value
                        MKTEQTY = market value of common equity ($millions)
   CSTATDS..............name of the data set containing the following
                        variables from the monthly COMPUSTAT input data
                        set:
                        PERMCO = cross-sectional (i.e., firm) identifier
                        DATE = SAS date value
                        DPT = default point ($millions)
                        NOTE: DPT = STDEBT + 0.5*LTDEBT
   IRATE................name of the risk-free interest rate in the CSTATDS
                        data set (APR).
   MAXITER..............positive integer specifying the maximum number of
                        iterations used to calculate the iterated estimate
                        of the volatility of the firm value.
                        NOTE: Default is MAXITER = 10
*/

%macro Merton_EDF(yyyy, mm, inds, irate, maxiter=10);


       /* Select the necessary time-series range from the INDS data set: */
       data _eds;
       set &inds;
           if (100*(&yyyy-1) + &mm) <= _cdt <= (100*&yyyy + &mm); 
       run;

       proc sort data=_eds;
       by permco date;
       run;

       /* Calculate the volatility of asset growth and identify
          large firms: */
       data _eds;
       set _eds;
           dlA = dif(log(A));
           by permco;
              do;
              if first.permco = 1 then
                 do;
                 dlA = .;
                 end;
              end;
       run;

       proc means data=_eds noprint;
       by permco;
       var dlA E D;
       output out=_statds;
       run;

       data _std _mean;
       set _statds;
           if _STAT_ = "STD" then output _std;
           if _STAT_ = "MEAN" then output _mean;
       run;

       data _std(keep=permco dlA_sigma);
       set _std;
           if _FREQ_ < 50 then delete;
           dlA_sigma = sqrt(252)*dlA;
           if dlA_sigma < 0.01 then dlA_sigma = 0.01;
       run;

       data _mean(keep=permco large);
       set _mean;
           large = 0;
           if D > 1000 and E > 1000 then large = 1;
       run;

       data _eds(drop=dlA);
       merge _eds(in=aa) _std(in=bb) _mean(in=cc);
       by permco;
       if aa=1 and bb=1 and cc=1;
          if large = 1 then
             do;
             D = D/100;
             E = E/100;
             A = A/100;
             end;
       run;

       data _convds;
            permco = 0;
       run;
       
       /* Calculate iterated volatility of the value of the firm: */
       %do k=1 %to &maxiter;
           %do;
           %numobs(inds=_eds);
           %if &nobs = 0 %then
               %do;
               %let k = &maxiter;
               %end;
           %if &nobs > 0 %then
               %do;
               ods listing close;
               proc model data=_eds;
               endogenous A;
               exogenous r D dlA_sigma E;
               /* Black-Sholes formula for the market value of the firm: */
	       E = A*probnorm((log(A/D) + (r + (dlA_sigma**2)/2))/dlA_sigma)
                   - D*exp(-r)*probnorm((log(A/D) + (r - (dlA_sigma**2)/2))/dlA_sigma);
               solve A / out=_out1 maxiter=500;
               outvars permco date;
               run;

               ods listing;
               
               data _out1;
               merge _out1(in=aa keep=permco date A) _eds(in=bb drop=A);
               by permco date;
               if aa=1 and bb=1;
               run;

               data _out1;
               set _out1;
                   dlA = dif(log(A));
                   by permco;
                      do;
                      if first.permco = 1 then
                         do;
                         dlA = .;
                         end;
                      end;
               run;

               proc means data=_out1 noprint;
               by permco;
               var dlA;
               output out=_statds1;
               run;

               data _mu _vol;
               set _statds1;
                   if _STAT_ = "MEAN" then output _mu;
                   if _STAT_ = "STD" then output _vol;
               run;

               data _mu(keep=permco mu_A);
               set _mu;
                   mu_A = 252*dlA;
               run;

               data _vol(keep=permco dlA_sigma1);
               set _vol;
                   dlA_sigma1 = sqrt(252)*dlA;
                   if dlA_sigma1 < 0.01 then dlA_sigma1 = 0.01;
               run;

               data _eds;
               merge _eds(in=aa) _mu(in=bb) _vol(in=cc);
               by permco;
               if aa=1 and bb=1 and cc=1;
                  _dif = dlA_sigma1 - dlA_sigma;
                  _CONV = 0;
                  if abs(_dif) < 0.001 and _dif ^= . then _CONV = 1;
               run;

               data _out2;
               set _eds(where=(_CONV=1));
                   sig_A = dlA_sigma;
               run;

               proc sort data=_out2;
               by permco descending date;
               run;
           
               data _out2;
               set _out2;
                   if permco ^= lag(permco);
                   _date = 100*&yyyy + &mm;
                   _iter = &k;
               run;

               data _convds(drop=dlA_sigma _CONV _cdt);
               merge _convds _out2;
               by permco;
               run;

               data _eds;
               set _eds(where=(_CONV=0));
                   dlA_sigma = dlA_sigma1;
                   drop dlA_sigma1;
               run;
               %end;
           %end;
           %end;

       
       data _convds(keep=permco date _ITER _dif E D A DD DD_merton EDF mu_A sig_A);
       format permco 8.;
       format date monyy7.;
       format large 1.;
       format _ITER 4.;
       format _dif 12.4;
       format E D A DD DD_merton EDF 8.4;
       format mu_A sig_A 7.3; 
       set _convds;
	  if permco = 0 or _date = 0 then delete;
          if large = 1 then
             do;
             A = 100*A;
             E = 100*E;
             D = 100*D;
             end;
          date = mdy(&mm, 1, &yyyy);
          DD = (A - D)/(A*sig_A);
          DD_merton = (log(A/D) + (mu_A - (sig_A**2)/2))/sig_A;
	  EDF = probnorm(-DD_merton);
          if D = 0 then
             do;
             DD = .;
             DD_merton = .;
             EDF = .;
             mu_A = .;
             sig_A = .;
             end;
	  label EDF = 'expected default frequency';
	  label DD = 'simple distance-to-default';
	  label DD_merton = 'Merton distance-to-default';
	  label E = 'market value of equity ($millions)';
	  label D = 'default point (STDEBT + 0.5*LTDEBT, $millions)';
	  label A = 'market value of the firm ($millions)';
          label mu_A = 'expected return on assets';
	  label sig_A = 'std. deviation (i.e., volatility) of A';
	  label _ITER = 'iterations required';
	  label _dif = 'final convergence criterion';
       run;

       
%mend Merton_EDF;

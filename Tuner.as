package
{
	import flash.display.Sprite;
	import flash.events.*;
	import flash.media.Microphone;
	import flash.text.*;
	import flash.utils.*;
	
    /******************************************************************************
	*
	*  Tuner.as - Basic Flash based (Guitar) Tuner class
	*  Robin van Emden, 2009
	*  
	*  Based on http://www.psychicorigami.com/2009/01/17/a-5k-java-guitar-tuner/
    * 	
	*  This Flash based web tuning application simply starts up 
	*  and tries to work out what note is being played. 
	*  It shows a basic slider that moves according to what note is being played 
	*  and indicates how close to that note you are. 
	*  In addition the raw frequency (in hz) is shown, 
	*  as well a chart that shows the autocorrelation function of the input sound. 
	*  A red line is drawn on this chart when a “valid” note is heard 
	*  and indicates the wavelength of the overall frequency.
	*
	*  Optimized for speed where possible.
	*
	********************************************************************************/
	
	[SWF(width='500', height='300', frameRate='20', backgroundColor='0xFFFFFF')]
	public final class Tuner extends Sprite
	{
	    private static const MIN_FREQ:Number = 0;					// Minimum frequency (Hz) on horizontal axis.
		private static const MAX_FREQ:Number = 2000;				// Maximum frequency (Hz) on horizontal axis.
		private static const FREQ_STEP:Number = 500;				// Interval between ticks (Hz) on horizontal axis.
		private static const MAX_DB:Number = -0.0;					// Maximum dB magnitude on vertical axis.
		private static const MIN_DB:Number = -60.0;				    // Minimum dB magnitude on vertical axis.
		private static const DB_STEP:Number = 10;					// Interval between ticks (dB) on vertical axis.
		private static const TOP:Number  = 0;						// Top of graph
		private static const LEFT:Number = 0;						// Left edge of graph
		private static const HEIGHT:Number = 299;					// Height of graph
		private static const WIDTH:Number = 499;					// Width of graph
		private static const TICK_LEN:Number = 10;					// Length of tick in pixels
		private static const LABEL_X:String = "Frequency (Hz)";	    // Label for X axis
		private static const LABEL_Y:String = "dB";				    // Label for Y axis
		private static const BOTTOM:Number = TOP+HEIGHT;
		private static const DBTOPIXEL:Number = HEIGHT/(MAX_DB-MIN_DB);
		private static const FREQTOPIXEL:Number = WIDTH/(MAX_FREQ-MIN_FREQ);		
		private static var y_local:Number;
		private static var x_local:Number;
		
		private static const SAMPLE_RATE:Number = 44100;	// Actual microphone sample rate (Hz)
		private static const LOGN:uint = 11;				// Log2 FFT length 11 orginal  // 10 == speed, maar niet voor lage tonen
		private static const N:uint = 1 << LOGN;			// FFT Length
		private static const BUF_LEN:uint = N;				// Length of buffer for mic audio
		private static const UPDATE_PERIOD:int = 100;       // Period of spectrum updates (ms)

		private static var m_tempRe:Vector.<Number>;		// Temporary buffer - real part
		private static var m_tempIm:Vector.<Number>;		// Temporary buffer - imaginary part
		private static var m_mag:Vector.<Number>;			// Magnitudes (at each of the frequencies below)
		private static var m_freq:Vector.<Number>;			// Frequencies (for each of the magnitudes above)
		private static var m_win:Vector.<Number>;			// Analysis window (Hanning)

		private static var m_mic:Microphone;				// Microphone object
		private static var m_writePos:uint = 0;				// Position to write new audio from mic
		private static var m_buf:Vector.<Number> = null;	// Buffer for mic audio
		private static var m_timer:Timer;					// Timer for updating spectrum
		
		// All defined as private static for max ActionScript speed:
		
		private static var len:int;
		private static var sampleLen:uint = 0;
		private static var lastSampleLen:uint = 0;		
		private static var prevDiff:Number = 0;
		private static var prevDx:Number = 0;
		private static var maxDiff:Number = 0;
		private static var dx:Number;			
		private static var diff:Number
		private static var j:uint;
		private static var i:uint;		
		private static var buff_diff:Number;
		private static var note:int;
		private static var thevalue:int = 0;
		private static var matchFreq:Number;
		private static var prevFreq:Number;
		private static var nextFreq:Number;		
		private static var frequency:Number;
		private static var mod:Number = 0;		
		private static var hps:Number = 0;
		private static var bin:int = 0;
		private static var sum:Number = 0;
		private static var maxamplitude:Number = 0;
		private static var iholder:uint = 0;
    	private static var FREQUENCIES:Array = [ 174.61, 164.81, 155.56, 146.83, 138.59, 130.81, 123.47, 116.54, 110.00, 103.83, 98.00, 92.50, 87.31, 82.41, 77.78];
    	private static var NAME:Array    = [ "F",    "E",    "D#",   "D",    "C#",   "C",    "B",    "A#",   "A",    "G#",   "G",   "F#",  "F",   "E",   "D#" ];
		private static var FREQ_RANGE:int = 128;
		private static var FREQUENCIES_LENGTH:int = FREQUENCIES.length;
        private static var points:Vector.<Number> ;
        private static var markers:Vector.<int> ;
		private static var playingout:Boolean = false;
		private static var min:Number = Number.MAX_VALUE, max = - Number.MAX_VALUE;
		private static var firstPoint:Boolean = true;
		private static var dist:Number;
		private static var minFreq:int = -1;
		private static var minDist:Number = Number.MAX_VALUE;
		private static var tempdiffbuff:Number;
		private static var numPoints:uint;
		
		public function Tuner()
		{
			freqLabel2.visible = false;
			
			background_mc.graphics.clear();

			// Draw a rectangular box marking the boundaries of the graph
			background_mc.graphics.lineStyle( 1, 0x000000 );
			background_mc.graphics.drawRect( LEFT, TOP, WIDTH, HEIGHT );
			background_mc.graphics.moveTo(LEFT, TOP+HEIGHT);
			freqLabel2.text= "--";
			
			points = new Vector.<Number>
			markers = new Vector.<int>
			
			freqSlider.minimum = -FREQ_RANGE;
			freqSlider.maximum = FREQ_RANGE;
			freqSlider.tickInterval = FREQ_RANGE/8;
			
			m_tempRe = new Vector.<Number>(N);
			m_tempIm = new Vector.<Number>(N);
			m_mag = new Vector.<Number>(N/2);

			m_freq = new Vector.<Number>(N/2);
			
			for ( i = 0; i < N/2; i++ ) {
				m_freq[i] = i*SAMPLE_RATE/N;
			}

			// Hanning analysis window
			m_win = new Vector.<Number>(N);
			for ( i = 0; i < N; i++ ) {
				m_win[i] = (4.0/N) * 0.5*(1-Math.cos(2*Math.PI*i/N));
			}
			// Create a buffer for the input audio
			m_buf = new Vector.<Number>(BUF_LEN);
			for ( i = 0; i < BUF_LEN; i++ ) {
				m_buf[i] = 0.0;
			}

			m_mic = Microphone.getMicrophone();
			m_mic.rate = SAMPLE_RATE/1000;
			m_mic.setSilenceLevel(0.0);		
			m_mic.addEventListener( SampleDataEvent.SAMPLE_DATA, onMicSampleData );

			m_timer = new Timer(UPDATE_PERIOD);
			m_timer.addEventListener(TimerEvent.TIMER, updateSpectrum);
			m_timer.start();

		}


    	private function normaliseFreq(hz:Number):Number {
			while ( hz < 82.41 ) {
				hz = hz << 1; //*2;
			}
			while ( hz > 164.81 ) {
				hz = hz >> 1; //*0.5
			}
			return hz;
    	}
    
    	private function closestNote(hz:Number):int {
			minDist = Number.MAX_VALUE;
			minFreq = -1;
			for (i = 0; i < FREQUENCIES_LENGTH; i++ ) {
				tempdiffbuff = FREQUENCIES[i]-hz;
				if (tempdiffbuff < 0)  tempdiffbuff = - tempdiffbuff;
				dist = tempdiffbuff;
				
				
				if ( dist < minDist ) {
					minDist=dist;
					minFreq=i;
				}
			}
			return minFreq;
    	}
		
		
		

		private function onMicSampleData( event:SampleDataEvent ):void
		{
			event.stopPropagation();
			
			// Gen number of available input samples
			var leng:uint = event.data.length/4;

			// Read the input data and stuff it into the circular buffer
			for ( i = 0; i < leng; i++ )
			{
				m_buf[int(m_writePos)] = event.data.readFloat();
				m_writePos = (m_writePos+1) & (BUF_LEN - 1) ;//%BUF_LEN;
			}
			
		}
		
   		private static var crossings:int;
    	private static var lastSample:Number;		
		
		private static var pos:uint;
		private function updateSpectrum( event:Event ):void
		{
			
			event.stopPropagation();	
			len = m_buf.length / 2;
			maxDiff = 0;
			sampleLen = 0;
			prevDx = 0;
			prevDiff = 0;
			thevalue = 0;
			
			clear();

			for ( i = iholder; i < len; i++ ) {

				diff = 0;
				for (j = 0; j < len; j++ ) {
					buff_diff = m_buf[j]-m_buf[int(i+j)];
					if (buff_diff < 0)  buff_diff = -buff_diff;
					diff += buff_diff;
				}
				add(diff);
                
				dx = prevDiff-diff;
				if ( dx < 0 && prevDx > 0 ) {
					if ( diff < (0.3*maxDiff) ) { 
						mark(i-1);
						if ( sampleLen == 0 ) {
							sampleLen=i-1;
						}
						prevDx = dx;
						prevDiff=diff;
						maxDiff=max2(diff,maxDiff);					
					}
				}
				prevDx = dx;
				prevDiff=diff;
				maxDiff=max2(diff,maxDiff);
			}

            if ( sampleLen > 0 ) {
				lastSampleLen = sampleLen;
				
                frequency = (SAMPLE_RATE/sampleLen);
                freqLabel.text = String(frequency.toFixed(2));
		
                frequency = normaliseFreq(frequency);
                note = closestNote(frequency);
                matchLabel.text = NAME[int(note)];
                prevLabel.text = NAME[int(note-1)];
                nextLabel.text = NAME[int(note+1)];
				
				thevalue = 0;
                matchFreq = FREQUENCIES[note];
                if ( frequency < matchFreq ) {
                    prevFreq = FREQUENCIES[note+1];
                    thevalue = int(-FREQ_RANGE*(frequency-matchFreq)/(prevFreq-matchFreq));
                }
                else {
                    nextFreq = FREQUENCIES[note-1];
                    thevalue = int(FREQ_RANGE*(frequency-matchFreq)/(nextFreq-matchFreq));
                }
                freqSlider.value = thevalue;
            }
            else {
					playingout = false;
                	matchLabel.text= "--";
					matchLabel.text= "--";
					if (freqLabel2.text!='--' && freqLabel2.text!=null) {
                	frequency = normaliseFreq(Number(freqLabel2.text));
                	note = closestNote(Number(freqLabel2.text));				
					matchLabel.text=NAME[note];
					}
                	prevLabel.text= "--";
                	nextLabel.text= "--";
                	freqSlider.value = 0;
                	freqLabel.text= "--";
			}			
	
			graphics.clear();
			drawSpectrumCOR( m_mag, m_freq );
		}

        public function max2(val1:Number, val2:Number): Number
        {
            if ((!(val1 <= 0) && !(val1 > 0)) || (!(val2 <= 0) && !(val2 > 0)))
            {
                return NaN;
            }
            return val1 > val2 ? val1 : val2;
        }
 
        public function min2(val1:Number, val2:Number): Number
        {
            if ((!(val1 <= 0) && !(val1 > 0)) || (!(val2 <= 0) && !(val2 > 0)))
            {
                return NaN;
            }
            return val1 < val2 ? val1 : val2;
        }
 
         private function clear():void {
            points.length = 0;
            markers.length = 0;
        }
        		
        private function add(value:Number):void  {
            points.push(value);
        }
        
        private function mark(pos1:int):void  {
            markers.push(pos1);
        }		
		
		private function drawSpectrumCOR(mag:Vector.<Number>, freq:Vector.<Number> ):void
		{
			numPoints = mag.length;
			if ( mag.length != freq.length )
				trace( "mag.length != freq.length" );
			min = Number.MAX_VALUE, max = - Number.MAX_VALUE;
			for (i = 0; i < numPoints && i<= WIDTH; i++ )
			{
                min = min2(points[i], min);
                max = max2(points[i], max);
            }
            
			
			graphics.lineStyle(1, 0x00FF00, 1);	
			firstPoint = true;
			for (i = 0; i <numPoints && i<= WIDTH; i++ )
			{
				x_local = LEFT + i;
				y_local = BOTTOM - (HEIGHT*(points[i]-min)/(max-min));
				
				if ( y_local < TOP )
					y_local = TOP;
				else if ( y_local > BOTTOM )
					y_local = BOTTOM;
				if ( firstPoint )
				{
					graphics.moveTo(x_local,y_local);
					firstPoint = false;
				}
				else
				{
					graphics.lineTo(x_local,y_local);
				}
			}
				
			for (i = 0; i < markers.length; i++ )
			{
				graphics.lineStyle(1, 0xFF0000, 1);			
				if (markers[i]<= WIDTH) x_local = LEFT + markers[i];
				graphics.moveTo(x_local,BOTTOM);
				graphics.lineTo(x_local,TOP)
				
			}
		}
	}
}

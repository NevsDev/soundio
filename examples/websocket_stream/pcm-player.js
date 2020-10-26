function PCMPlayer(option) {
  this.init(option);
}

PCMPlayer.prototype.init = function(option) {
  var defaults = {
      encoding: 'int16',
      channels: 1,
      sampleRate: 8000,
      flushingTime: 1000
  };
  this.option = Object.assign({}, defaults, option);
  this.samples = new Float32Array();
  this.flush = this.flush.bind(this);
  this.interval = setInterval(this.flush, this.option.flushingTime);
  this.maxValue = this.getMaxValue();
  this.valueOffset = this.getValueOffset();
  this.typedArray = this.getTypedArray();
  this.createContext();
};

PCMPlayer.prototype.getMaxValue = function () {
  var encodings = {
      'int8': 128,
      'uint8': 128,
      'int16': 32768,
      'uint16': 32768,
      'int32': 2147483648,
      'uint32': 2147483648,
      'float32': 1,
      'float64': 1
  }

  return encodings[this.option.encoding] ? encodings[this.option.encoding] : encodings['int16'];
};

PCMPlayer.prototype.getValueOffset = function () {
  var offset = {
      'int8': 0,
      'uint8': -128,
      'int16': 0,
      'uint16': -32768,
      'int32': 0,
      'uint32': -2147483648,
      'float32': 0,
      'float64': 0
  }

  return offset[this.option.encoding] ? offset[this.option.encoding] : offset['int16'];
};

PCMPlayer.prototype.getTypedArray = function () {
  var typedArrays = {
      'int8': Int8Array,
      'uint8': Uint8Array,
      'int16': Int16Array,
      'uint16': Uint16Array,
      'int32': Int32Array,
      'uint32': Uint32Array,
      'float32': Float32Array,
      'float64': Float64Array
  }

  return typedArrays[this.option.encoding] ? typedArrays[this.option.encoding] : typedArrays['int16'];
};

PCMPlayer.prototype.createContext = function() {
  this.audioCtx = new (window.AudioContext || window.webkitAudioContext)();
  this.gainNode = this.audioCtx.createGain();
  this.gainNode.gain.value = 1;
  this.gainNode.connect(this.audioCtx.destination);
  this.startTime = this.audioCtx.currentTime;
};

PCMPlayer.prototype.isTypedArray = function(data) {
  return (data.byteLength && data.buffer && data.buffer.constructor == ArrayBuffer);
};

PCMPlayer.prototype.feed = function(data) {
  if (!this.isTypedArray(data)) return;
  data = this.getFormatedValue(data);
  var tmp = new Float32Array(this.samples.length + data.length);
  tmp.set(this.samples, 0);
  tmp.set(data, this.samples.length);
  this.samples = tmp;
};

PCMPlayer.prototype.getFormatedValue = function(data) {
  var data = new this.typedArray(data.buffer),
      float32 = new Float32Array(data.length),
      i;

  if(this.option.encoding != "float32")
    for (i = 0; i < data.length; i++)
        float32[i] = (data[i] + this.valueOffset) / this.maxValue;
  return float32;
};

PCMPlayer.prototype.volume = function(volume) {
  this.gainNode.gain.value = volume;
};

PCMPlayer.prototype.destroy = function() {
  if (this.interval) {
      clearInterval(this.interval);
  }
  this.samples = null;
  this.audioCtx.close();
  this.audioCtx = null;
};

PCMPlayer.prototype.flush = function() {
  if (!this.samples.length) return;
  var bufferSource = this.audioCtx.createBufferSource(),
      length = this.samples.length / this.option.channels,
      audioBuffer = this.audioCtx.createBuffer(this.option.channels, length, this.option.sampleRate),
      audioData,
      channel,
      offset,
      i,
      decrement;

  for (channel = 0; channel < this.option.channels; channel++) {
      audioData = audioBuffer.getChannelData(channel);
      offset = channel;
      decrement = 50;
      for (i = 0; i < length; i++) {
          audioData[i] = this.samples[offset];
          /* fadein */
          if (i < 50) {
              audioData[i] =  (audioData[i] * i) / 50;
          }
          /* fadeout*/
          if (i >= (length - 51)) {
              audioData[i] =  (audioData[i] * decrement--) / 50;
          }
          offset += this.option.channels;
      }
  }
  
  if (this.startTime < this.audioCtx.currentTime) {
      this.startTime = this.audioCtx.currentTime;
  }
  console.log('start vs current '+this.startTime+' vs '+this.audioCtx.currentTime+' duration: '+audioBuffer.duration);
  bufferSource.buffer = audioBuffer;
  bufferSource.connect(this.gainNode);
  bufferSource.start(this.startTime);
  this.startTime += audioBuffer.duration;
  this.samples = new Float32Array();
};
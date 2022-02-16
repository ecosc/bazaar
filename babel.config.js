module.exports = (api) => {
    // Cache configuration is a required option
    api.cache(false);
  
    const presets = [
      [
        "@babel/preset-env", 
        { 
          useBuiltIns: "usage",
          corejs: 2,
        }
      ]
    ];
  
    return { presets };
  };
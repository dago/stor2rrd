var hashTable = {};
var sysInfo = {};
var curLoad;
var curNode;
var curTab;
var jumpTo;
var browserNavButton = false;
var storedUrl;
var zoomedUrl;
var storedObj;
var timeoutHandle;

var tabHead = {
	'total': "Total",
	'read': "Read",
	'write': "Write",
	'resp': "Response time total",
	'resp tot': "Response time total",
	'resp read': "Response time read",
	'resp write': "Response time write",
	'resp read back': "Response time read - back",
	'resp write back': "Response time write - back",
	'resp_t_r_b': "Response time read - back",
	'resp_t_w_b': "Response time write - back",
	'sum_io': "IO total",
	'sum_data': "Data total",
	'IO tot': "IO total",
	'io_rate': "IO total",
	'data tot': "Data total",
	'data_rate': "Data total",
	'IO read': "IO Read",
	'IO write': "IO Write",
	'IO read back': "IO Read - back",
	'IO write back': "IO Write - back",
	'read_io_b': "IO Read - back",
	'write_io_b': "IO Write - back",
	'read back': "Read data - back",
	'write back': "Write data - back",
	'read avg': "Read average",
	'write avg': "Write average",
	'read usage': "Read usage",
	'write usage': "Write usage",
	'read hit': "Read hit",
	'write hit': "Write hit",
	'sys': "CPU system",
	compress: "CPU compress",
	sum_capacity: "Capacity",
	used: "Capacity used",
	real: "Capacity real",
	r_cache_usage: "Read cache usage",
	w_cache_usage: "Write cache usage",
	'read cache hit': "Read cache hit",
	'write cache hit': "Write cache hit",
	pprc_rio: "PPRC read IO",
	pprc_wio: "PPRC write IO",
	pprc_data_r: "PPRC read data",
	pprc_data_w: "PPRC write data",
	pprc_rt_r: "PPRC response time read",
	pprc_rt_w: "PPRC response time write",
	"CPU": "CPU node",
	io_cntl: "controller",
	ssd_r_cache_hit: "SSD read cache hit",
	cache_hit: "cache hit",
	data_cntl: "controller",
	read_pct: "read percent"
};

var urlItem = {
	resp: "response time total",
	resp_t: "response time total",
	resp_t_r: "response time read",
	resp_t_w: "response time write",
	resp_t_r_b: "response time read - back",
	resp_t_w_b: "response time write - back",
	sum_io: "io total",
	sum_data: "data total",
	io: "io total",
	io_rate: "io total",
	data: "data total",
	data_rate: "data total",
	read_io: "read io",
	write_io: "write io",
	read_io_b: "read io - back",
	write_io_b: "write io - back",
	read: "read data",
	write: "write data",
	read_b: "read data - back",
	write_b: "write data - back",
	sys: "cpu system",
	compress: "cpu compress",
	sum_capacity: "capacity",
	used: "capacity used",
	real: "capacity real",
	r_cache_usage: "read cache usage",
	w_cache_usage: "write cache usage",
	r_cache_hit: "read cache hit",
	w_cache_hit: "write cache hit",
	pprc_rio: "pprc read io",
	pprc_wio: "pprc write io",
	pprc_data_r: "pprc read data",
	pprc_data_w: "pprc write data",
	pprc_rt_r: "pprc response time read",
	pprc_rt_w: "pprc response time write",
	io_cntl: "controller",
	ssd_r_cache_hit: "SSD read cache hit",
	cache_hit: "cache hit",
	data_cntl: "controller",
	read_pct: "read percent"
};

// cap, io, data, resp, cache, cpu, pprc


if (!Object.keys) { // IE8 hack
	Object.keys = function(obj) {
		var keys = [];

		for (var i in obj) {
			if (obj.hasOwnProperty(i)) {
				keys.push(i);
			}
		}

		return keys;
	};
}

var urlItems = Object.keys(urlItem);

var intervals = {
	d: "Last day",
	w: "Last week",
	m: "Last month",
	y: "Last year"
};

$(document).ready(function() {
	$.ajaxSetup({
		traditional: true
	});

	// Bind to StateChange Event
	History.Adapter.bind(window, 'statechange', function() { // Note: We are using statechange instead of popstate
		var state = History.getState(); // Note: We are using History.getState() instead of event.state
		var menuTree = $("#side-menu").fancytree("getTree");
		if (state.data.menu && state.internal) {
			curTab = state.data.tab;
			browserNavButton = true;
			if (state.data.form) {
				var data = restoreData(state.data.form);
				$("#content").html(data.html);
				myreadyFunc();
				$("#content").scrollTop(data.scroll);
				$("#title").html(data.title);
			} else if (state.data.menu == menuTree.getActiveNode().key) {
				menuTree.reactivate();
			} else {
				menuTree.activateKey(state.data.menu);
			}
		}
	});


	$.getJSON("/stor2rrd-cgi/genjson.sh?jsontype=env", function(data) {
		$.each(data, function(key, val) {
			sysInfo[key] = val;
		});
		if (sysInfo.beta == "1") {
			if (!$.cookie('beta-notice')) {
				$.cookie('beta-notice', 'displayed', {
					expires: 0.25
				}); // 0.007 = 10 minutes
				$("#beta-notice").load("beta-notice.html");
				$("#beta-notice").dialog("open");
			}
		}
		if (sysInfo.guidebug == 1) {
			$("#savecontent input:submit").button();
			$("#savecontent").show();
		}
	});
	$("#beta-notice").dialog({
		dialogClass: "info",
		minWidth: 500,
		modal: true,
		autoOpen: false,
		show: {
			effect: "fadeIn",
			duration: 500
		},
		hide: {
			effect: "fadeOut",
			duration: 200
		},
		buttons: {
			OK: function() {
				$(this).dialog("close");
			}
		}
	});
	$("#data-src-info").dialog({
		dialogClass: "info",
		minWidth: 400,
		modal: true,
		autoOpen: false,
		show: {
			effect: "fadeIn",
			duration: 500
		},
		hide: {
			effect: "fadeOut",
			duration: 200
		},
		position: {
			my: "right top",
			at: "right top",
			of: $("#content")
		},
		buttons: {
			OK: function() {
				$(this).dialog("close");
			}
		}
	});
	$("#rperf-notice").dialog({
		dialogClass: "info",
		minWidth: 500,
		modal: true,
		autoOpen: false,
		show: {
			effect: "fadeIn",
			duration: 500
		},
		hide: {
			effect: "fadeOut",
			duration: 200
		},
		buttons: {
			OK: function() {
				$(this).dialog("close");
			}
		}
	});

	$("#side-menu").fancytree({
		extensions: ["filter", "persist"],
		source: {
			url: '/stor2rrd-cgi/genjson.sh?jsontype=menuh'
		},
		filter: {
			mode: "hide"
		},
		icons: false,
		selectMode: 1,
		clickFolderMode: 2,
		activate: function(event, data) {
			if (curNode != data.node) {
				if (curNode && !browserNavButton) {
					curTab = 0;
				}
				curNode = data.node;
			}
			if (curNode.data.href) {
				autoRefresh();
				var url = curNode.data.href;
				if (curLoad) {
					curLoad.ajaxStop(); //cancel previous load
				}
				$('#content').empty();
				$('#content').append("<div style='width: 100%; height: 100%; text-align: center'><img src='css/images/sloading.gif' style='margin-top: 200px'></div>");
				$('#subheader fieldset').hide();
				curLoad = $('#content').load(url, function() {
					imgPaths();
					setTimeout(function() {
						myreadyFunc();
						setTitle(curNode);
						var tabName = "";
						if ($('#tabs').length) {
							tabName = " [" + $('#tabs li.ui-tabs-active').text() + "]";
						}
						if (curNode.data.hash) {
							urlMenu = curNode.data.hash;
						} else {
							urlMenu = curNode.key.substring(1);
						}
						History.pushState({
							menu: curNode.key,
							tab: curTab
						}, "STOR2RRD - " + $('#title').text() + tabName, '?menu=' + urlMenu + "&tab=" + curTab);
						browserNavButton = false;
					}, 10);
				});
			}
		},
		click: function(event, data) { // allow re-loads
			var node = data.node;
			if (!node.isExpanded()) {  // jump directly to POOL/IO when opening storage
				if (node.getLevel() == 2) {
					node.visit(function(chNode) {
						if ( sysInfo.jump_to_rank && (chNode.title == "RANK" || chNode.title == "Managed disk" ) || (!sysInfo.jump_to_rank && chNode.title == "POOL") ) {
							chNode.visit(function(pNode) {
								if (pNode.title == "IO") {
									event.preventDefault();
									pNode.setActive();
									pNode.makeVisible({
										noAnimation: true,
										noEvents: true,
										scrollIntoView: true
									});
									// chNode.setExpanded()
									return false;
								}
							});
						}
					});
				}
				else if (node.getLevel() == 3) {
					node.visit(function(chNode) {
						if ( chNode.title == "IO") {
							event.preventDefault();
							chNode.setActive();
							chNode.makeVisible({
								noAnimation: true,
								noEvents: true,
								scrollIntoView: true
							});
							// chNode.setExpanded()
							return false;
						}
					});
				}
			}
			if (node.isActive() && node.data.href) {
				data.tree.reactivate();
			}
		},
		init: function() {
			var $tree = $(this).fancytree("getTree");
			var menuPos = getUrlParameter('menu');
			var tabPos = getUrlParameter('tab');
			if (tabPos) {
				curTab = tabPos;
			}
			if (menuPos) {
				if (menuPos == "extnmon") {
					var href = window.location.href;
					var qstr = href.slice(href.indexOf('&start-hour') + 1);
					var hashes = qstr.split('&');
					// var txt = hashes[13].split("=")[1];
					var txt = decodeURIComponent(hashes[14].split("=")[1]);

					txt = txt.replace("--unknown","");
					txt = txt.replace("--NMON--","");
					$("#content").load("/lpar2rrd-cgi/lpar2rrd-external-cgi.sh?" + qstr, function(){
						imgPaths();
						$('#title').text(txt);
						$('#title').show();
						myreadyFunc();
						// loadImages('#content img.lazy');
						if (timeoutHandle) {
							clearTimeout(timeoutHandle);
						}
					});
				} else {
					$tree.visit(function(node) {
						if (node.data.hash == menuPos) {
							node.setExpanded(true);
							node.setActive();
							return false;
						}
					});
				}
			}
			else if (!$tree.activeNode) {
				$tree.getFirstChild().setActive();
			}
			hashTable = [];
			$tree.visit(function(node) {
				if (sysInfo.guidebug == 1) {
					node.tooltip = node.data.href;
					node.renderTitle();
				}
				if (node.data.hash) {
					if (node.data.agg) {
						hashTable[node.data.hash] = {
							"hmc": node.data.hmc,
							"srv": node.data.srv,
							"lpar": "sum"
						};
					} else if (node.data.altname) {
						hashTable[node.data.hash] = {
							"hmc": node.data.hmc,
							"srv": node.data.srv,
							"lpar": node.data.altname,
							"longname": node.title
						};
					} else {
						hashTable[node.data.hash] = {
							"hmc": node.data.hmc,
							"srv": node.data.srv,
							"lpar": node.title
						};
					}
				}
			});
		}
	});

	var $tree = $("#side-menu").fancytree("getTree");

	$("#lparsearch").submit(function(event) {
		event.preventDefault();
		if (timeoutHandle) {
			clearTimeout(timeoutHandle);
		}
		$('#content').empty();

		$('#content').append("<div style='width: 100%; height: 100%; text-align: center'><img src='css/images/sloading.gif' style='margin-top: 200px'></div>");
		$('#title').text("LPAR search results");
		var postData = $(this).serialize();
		if (sysInfo.guidebug == 1) {
			copyToClipboard(postData);
		}
		$('#content').load(this.action, postData, function() {
			if (curNode.data.hash) {
				urlMenu = curNode.data.hash;
			} else {
				urlMenu = curNode.key.substring(1);
			}
			History.pushState({
				menu: curNode.key,
				tab: curTab,
				form: "lparsrch"
			}, "LPAR2RRD - LPAR Search Form Results", '?menu=' + urlMenu + "&tab=" + curTab);
			imgPaths();
			myreadyFunc();
			saveData("lparsrch"); // save when page loads

		});
	});

	/* BUTTONS */

	$("#collapseall").button({
		text: false,
		icons: {
			primary: "ui-icon-minus"
		}
	})
		.click(function() {
			$tree.visit(function(node) {
				node.setExpanded(false, {
					noAnimation: true,
					noEvents: true
				});
			});
		});
	$("#expandall").button({
		text: false,
		icons: {
			primary: "ui-icon-plus"
		}
	})
		.click(function() {
			$tree.visit(function(node) {
				node.setExpanded(true, {
					noAnimation: true,
					noEvents: true
				});
			});
		});
	$("#filter").button({
		text: false,
		icons: {
			primary: "ui-icon-search"
		}
	})
		.click(function() {
			// Pass text as filter string (will be matched as substring in the node title)
			var match = $("#menu-filter").val();
			if ($.trim(match) !== "") {
				var re = new RegExp(match, "i");
				var n = $tree.filterNodes(function(node) {
					var parentTitle = node.parent.title;
					var matched = re.test(node.data.str);
					if (matched) {
						node.setExpanded(true, true);
						if (parentTitle != "Removed") {
							if ((parentTitle != "Items") || ((parentTitle == "Items") && re.test(node.title))) {
								node.makeVisible({
									noAnimation: true,
									noEvents: true,
									scrollIntoView: false
								});
							}
						}
					}
					return matched;
				});
				// $("#expandall").click();
				$("#clrsrch").button("enable");
			}
		});

	$("#clrsrch").button({
		text: false,
		disabled: true,
		icons: {
			primary: "ui-icon-close"
		}
	})
		.click(function() {
			$("#menu-filter").val("");
			$tree.clearFilter();
			$(this).button("disable");
		});

	/*
	* Event handlers for menu filtering
	*/
	$("#menu-filter").keypress(function(event) {
		var match = $(this).val();
		if (event.which == 13) {
			event.preventDefault();
			if (match > "") {
				$("#filter").click();
			}
		}
		if (event.which == 27 || $.trim(match) === "") {
			$("#clrsrch").click();
		}
	}).focus();

	if (navigator.userAgent.indexOf('MSIE') >= 0) { // MSIE
		placeholder();
		$("input[type=text]").focusin(function() {
			var phvalue = $(this).attr("placeholder");
			if (phvalue == $(this).val()) {
				$(this).val("");
			}
		});
		$("input[type=text]").focusout(function() {
			var phvalue = $(this).attr("placeholder");
			if ($(this).val() === "") {
				$(this).val(phvalue);
			}
		});
		$("#menu-filter").blur();
	}

	$("#savecontent").submit(function(event) {
		var conf = confirm("This will generate file named <debug.txt> containing HTML code of main page. Please save it to disk and attach to the bugreport");
		if (conf === true) {
			var postDataObj = {
				html: "<!-- " + navigator.userAgent + "-->\n" + $("#content").html()
			};
			var postData = "<!-- " + navigator.userAgent + "-->\n" + $("#content").html();
			$("#tosave").val(postData);
			return;
		} else {
			event.preventDefault();
		}

	});
	$("#switchstyle").change(function() {
		if ($(this).is(":checked")) {
			$('#style[rel=stylesheet]').attr("href", "css/darkstyle.css");
		} else {
			$('#style[rel=stylesheet]').attr("href", "css/style.css");
		}
	});
	$("#menusw").buttonset();

	$("#menusw").change(function() {
		if ($("#ms1").is(":checked")) {
			$("#side-menu").fancytree("getTree").reload({
				url: '/stor2rrd-cgi/genjson.sh?jsontype=menu'
			});
		} else {
			$("#side-menu").fancytree("getTree").reload({
				url: '/stor2rrd-cgi/genjson.sh?jsontype=menuh'
			});
		}
	});

});

function imgPaths() {
	$('#content img').each(function() { /* subpage without tabs */
		var imgsrc = $(this).attr("src");
		if (/loading\.gif$/.test(imgsrc)) {
			$(this).attr("src", 'css/images/sloading.gif');
		} else if (!/\//.test(imgsrc)) {
			var n = $('#side-menu').fancytree('getActiveNode');
			var url = n.data.href;

			$(this).attr("src", url.substr(0, url.lastIndexOf('/') + 1) + imgsrc);
		}
	});
}

function autoRefresh() {
	if (timeoutHandle) {
		clearTimeout(timeoutHandle);
	}
	timeoutHandle = setTimeout(function() {
		$("#side-menu").fancytree("getTree").reactivate();
		autoRefresh();
	}, 600000); /* 600000 = 10 minutes */
}

/********* Execute after new content load */

function myreadyFunc() {

	var dbHashes = $.cookie('dbHashes');
	$("div.zoom").uniqueId();

	if (!dbHashes) {
		dbHash = [];
	} else {
		dbHash = dbHashes.split(":");
	}

	$('#tabs').tabs({
		active: curTab,
		beforeLoad: function( event, ui ) {
			ui.panel.html('<img src="css/images/sloading.gif" style="display: block; margin-left: auto; margin-right: auto; margin-top: 10em" />');
		},
		activate: function(event, ui) {
			curTab = ui.newTab.index();
			var tabName = "";
			if ($("#tabs").length) {
				tabName = " [" + $('#tabs li.ui-tabs-active').text() + "]";
			}
			if (curNode) {
				if (curNode.data.hash) {
					urlMenu = curNode.data.hash;
				} else {
					urlMenu = curNode.key.substring(1);
				}
				History.pushState({
					menu: curNode.key,
					tab: curTab
				}, "STOR2RRD - " + $("#title").text() + tabName, '?menu=' + curNode.key.substring(1) + "&tab=" + curTab);
			}
			setTitle(curNode);

			if ($("#emptydash").length) {
				$("ul.dashlist").empty();
				genDashboard();
				autoRefresh();
			} else {
				autoRefresh();
				loadImages(ui.newPanel.selector + " img.lazy");
				hrefHandler();
				dataSource();
				showHideSwitch();
				sections();
			}
		},
		load: function(event, ui) {
			hrefHandler();
			var $t = ui.panel.find('table.tablesorter');
			if ($t.length) {
				tableSorter($t);
			}
		}
	});

	setTimeout(function() {
		if ($("#tabs").length) {
			loadImages("div[aria-hidden=false] img.lazy");
		} else {
			loadImages('#content img.lazy');
		}
		dataSource();
	}, 100);

	$("table.tablesorter").each(function() {
		tableSorter(this);
	});

	hrefHandler();

	$("#subheader fieldset").hide();

	$("#nmonsw").buttonset();

	$("#nmonsw").click(function() {
		sections();
		var newTabHref = '';
		var activeTab = $('#tabs li.ui-tabs-active.tabfrontend,#tabs li.ui-tabs-active.tabbackend').text();
		showHideSwitch();
		if (activeTab) {
			if ($("#nmr1").is(':checked')) {
				newTabHref = $('#tabs li.tabfrontend a:contains("' + activeTab + '")').attr("href");
			} else {
				newTabHref = $('#tabs li.tabbackend a:contains("' + activeTab + '")').attr("href");
			}
			$("[href='" + newTabHref + "']").trigger("click");
		}
	});

	if ( $("#histrep").length ) {
		var checkedBoxes = $.cookie('HistFormCheckBoxes');
		if ( !checkedBoxes ) {
			// Set basic set of output data if not defined
			checkedBoxes = ["io_rate", "read_io", "write_io", "data_rate", "read", "write"];
		}
		$.each(checkedBoxes, function(index, value) {
			$( "input:checkbox[value=" + value + "]" ).prop('checked', true);
		});
	}

	$("#radio").buttonset();
	$("#radiosrc").buttonset();

	$("input[type=checkbox][name=lparset]").change(function() {
		if ($("#radios2").is(':checked')) {
			$("#lpartree").fancytree("getTree").reload({
				url: '/stor2rrd-cgi/genjson.sh?jsontype=hmcsel'
			});
			$("#lparfieldset legend").text("HMC | Server | LPAR");
		} else {
			$("#lpartree").fancytree("getTree").reload({
				url: '/stor2rrd-cgi/genjson.sh?jsontype=lparsel'
			});
			$("#lparfieldset legend").text("Server | LPAR");
		}
	});

	fancyBox();

	function fancyBox() {
		$('a.detail').fancybox({
			type: 'image',
			openEffect: 'none',
			closeEffect: 'none',
			live: false,
			openSpeed: 400,
			closeSpeed: 100,
			fitToView: false, // images won't be scaled to fit to browser's height
			maxWidth: "98%",
			overlay: {
				showEarly: false,
				css: {
					'background': 'rgba(58, 42, 45, 0.95)'
				}
			},
			closeClick: true,
			beforeLoad: function() {
				if (storedUrl) {
					this.href = zoomedUrl;
				} else {
					var tUrl = this.href;
					tUrl += "&none=" + Math.floor(new Date().getTime() / 1000);
					this.href = tUrl;
				}
				return true;
			},
			afterClose: function() {
				if (storedUrl) {
					$(storedObj).attr("href", storedUrl);
					storedUrl = "";
					storedObj = {};
				}
			}
		});
	}

	var now = new Date();
	var twoWeeksBefore = new Date();
	var yesterday = new Date();
	var nowPlusHour = new Date();
	yesterday.setDate(now.getDate() - 1);
	twoWeeksBefore.setDate(now.getDate() - 14);
	nowPlusHour.setHours(now.getHours() + 1);


	var startDateTextBox = $('#fromTime');
	var endDateTextBox = $('#toTime');

	$("#fromTime").datetimepicker({
		defaultDate: '-1d',
		dateFormat: "yy-mm-dd",
		timeFormat: "HH:00",
		maxDate: nowPlusHour,
		changeMonth: true,
		changeYear: true,
		showButtonPanel: true,
		showMinute: false,
		onClose: function(dateText, inst) {
			if (endDateTextBox.val() !== '') {
				var testStartDate = startDateTextBox.datetimepicker('getDate');
				var testEndDate = endDateTextBox.datetimepicker('getDate');
				if (testStartDate > testEndDate) {
					endDateTextBox.datetimepicker('setDate', testStartDate);
				}
			} else {
				endDateTextBox.val(dateText);
			}
		},
		onSelect: function(selectedDateTime) {
			endDateTextBox.datetimepicker('option', 'minDate', startDateTextBox.datetimepicker('getDate'));
		}
	});
	if ($("#fromTime").length) {
		var fromTime = $.cookie('fromTimeField');
		if ( fromTime ) {
			$("#fromTime").datetimepicker("setDate", fromTime);
		} else {
			$("#fromTime").datetimepicker("setDate", yesterday);
		}
	}

	$("#toTime").datetimepicker({
		defaultDate: 0,
		dateFormat: "yy-mm-dd",
		timeFormat: "HH:00",
		maxDate: nowPlusHour,
		changeMonth: true,
		changeYear: true,
		showButtonPanel: true,
		showMinute: false,
		onClose: function(dateText, inst) {
			if (startDateTextBox.val() !== '') {
				var testStartDate = startDateTextBox.datetimepicker('getDate');
				var testEndDate = endDateTextBox.datetimepicker('getDate');
				if (testStartDate > testEndDate) {
					startDateTextBox.datetimepicker('setDate', testEndDate);
				}
			} else {
				startDateTextBox.val(dateText);
			}
		},
		onSelect: function(selectedDateTime) {
			startDateTextBox.datetimepicker('option', 'maxDate', endDateTextBox.datetimepicker('getDate'));
		}
	});
	if ($("#toTime").length) {
		var toTime = $.cookie('toTimeField');
		if ( toTime ) {
			$("#toTime").datetimepicker("setDate", toTime);
		} else {
			$("#toTime").datetimepicker("setDate", now);
		}
	}

	// History reports form submit
	$("#histrep").submit(function(event) {
		var outputDataCount = $( "input:checked[name=output]" ).length;
		if (!outputDataCount) {
			alert("Please select at least one data output for report!");
			return false;
		}

		var $poolTree = $("#pooltree").fancytree("getTree");
		var $portTree = $("#porttree").fancytree("getTree");
		var $rankTree = $("#ranktree").fancytree("getTree");
		var $voluTree = $("#voltree").fancytree("getTree");

		var selCount = 0;
		var pota, prta, rata, vota;

		if ($poolTree.length !== 0) {
			selCount += $poolTree.getSelectedNodes().length;
			$poolTree.generateFormElements(true, false, false);
			pota = 'ft_' + $poolTree._id + "[]";
		}
		if ($portTree.length !== 0) {
			selCount += $portTree.getSelectedNodes().length;
			$portTree.generateFormElements(true, false, false);
			prta = 'ft_' + $portTree._id + "[]";
		}
		if ($rankTree.length !== 0) {
			selCount += $rankTree.getSelectedNodes().length;
			$rankTree.generateFormElements(true, false, false);
			rata = 'ft_' + $rankTree._id + "[]";
		}
		if ($voluTree.length !== 0) {
			selCount += $voluTree.getSelectedNodes().length;
			$voluTree.generateFormElements(true, false, false);
			vota = 'ft_' + $voluTree._id + "[]";
		}

		if ( selCount === 0) {
			alert("Please select at least one item for report");
			return false;
		}

		var fromDate = $("#fromTime").datetimepicker("getDate");
		var toDate = $("#toTime").datetimepicker("getDate");

		$.cookie('fromTimeField', fromDate, {
            expires: 0.04
        });
		$.cookie('toTimeField', toDate, {
            expires: 0.04
        });

		$("#start-hour").val(fromDate.getHours());
		$("#start-day").val(fromDate.getDate());
		$("#start-mon").val(fromDate.getMonth() + 1);
		$("#start-yr").val(fromDate.getFullYear());

		$("#end-hour").val(toDate.getHours());
		$("#end-day").val(toDate.getDate());
		$("#end-mon").val(toDate.getMonth() + 1);
		$("#end-yr").val(toDate.getFullYear());

		// get HMC & server name from menu url
		// var serverPath = $("#side-menu").fancytree('getActiveNode').data.href.split('/');
		var storage = curNode.parent.title;
		$("#storage").val(storage);

		var checkedBoxes = $("input:checkbox:checked.allcheck, input:checkbox:checked[name=output]").map(function () {
			return this.value;
		}).get();
		$.cookie('HistFormCheckBoxes',checkedBoxes, {
			expires: 60
		});

		// exclude allcheck boxes
		$(this).find(":checkbox.allcheck").attr("disabled", true);

		// remove parent items if whole branch checked
		var postArray = $(this).serializeArray();
		for (var i = 0; i < postArray.length; i++) {
			if (postArray[i].value.indexOf('_') === 0) {
				postArray.splice(i, 1);
				i--;
			}
		}
		// replace fancytree fieldnames ft_...
		$.each(postArray, function(index, value) {
			if (value.name == pota) {
				value.name = 'POOL';
			} else if (value.name == prta) {
				value.name = 'PORT';
			} else if (value.name == rata) {
				value.name = 'RANK';
			} else if (value.name == vota) {
				value.name = 'VOLUME';
			}
		});
		var postData = $.param(postArray);

		if (sysInfo.guidebug == 1) {
			copyToClipboard(postData);
			// alert("POST data:\n" + postData);
		}

		$('#content').load(this.action, postArray, function() {
			if (curNode.data.hash) {
				urlMenu = curNode.data.hash;
			} else {
				urlMenu = curNode.key.substring(1);
			}
			History.pushState({
				menu: curNode.key,
				tab: curTab,
				form: "hrep"
			}, "STOR2RRD - " + $('#title').text(), '?menu=' + curNode.key.substring(1) + "&tab=" + curTab + "&form=");
			imgPaths();
			myreadyFunc();
			saveData("hrep"); // save when page loads
		});
		event.preventDefault();
		if (timeoutHandle) {
			clearTimeout(timeoutHandle);
		}
	});

	//*************** Remove unwanted parent classes
	$('#content table.tabsyscfg').has('table').removeClass('tabsyscfg');
	$('#content table.tabtop10').has('table').removeClass('tabtop10');

	showHideSwitch();

	if (navigator.userAgent.indexOf('MSIE 8.0') < 0) {
		$('#content a:not(.nowrap):contains("How it works")').wrap(function() {
			var url = this.href;
			return "<div id='hiw'><a href='" + url + "' target='_blank'><img src='css/images/help-browser.gif' alt='How it works?' title='How it works?'></a></div>";
		});
	}

	$("#datasrc").click(function() {
		$("#data-src-info").dialog("open");
	});

	$("#pooltree").fancytree({
		extensions: ["persist"],
		persist: {
			cookiePrefix: "pooltree-"
		},
		clickFolderMode: 2,
		checkbox: true,
		selectMode: 2,
		/* init: function (){
$(this).fancytree("option", "selectMode", 3);
$(this).fancytree("getTree").getFirstChild().fixSelection3FromEndNodes();
},
*/
		icons: false,
		autoCollapse: true,
		source: {
			url: '/stor2rrd-cgi/genjson.sh?' + histRepQueryString('POOL')
		}
	});
	$("#srvlparfilter").keyup(function(e){
		var n,
			match = $(this).val();
		var $ltree = $("#voltree").fancytree("getTree");

		if (e && e.which === $.ui.keyCode.ESCAPE || $.trim(match) === "") {
			$ltree.clearFilter();
			return;
		}
		n = $ltree.filterNodes(function (node) {
			return new RegExp(match, "i").test(node.title);
		}, true);
		$ltree.visit(function(node){
			if (!$(node.span).hasClass("fancytree-hide")) {
				node.setExpanded(true);
			}
		});
	}).focus();
	$("#porttree").fancytree({
		extensions: ["persist"],
		persist: {
			cookiePrefix: "porttree-"
		},
		clickFolderMode: 2,
		checkbox: true,
		selectMode: 2,
		icons: false,
		autoCollapse: true,
		source: {
			url: '/stor2rrd-cgi/genjson.sh?' + histRepQueryString('PORT')
		}
	});

	$("#ranktree").fancytree({
		extensions: ["persist"],
		persist: {
			cookiePrefix: "ranktree-"
		},
		clickFolderMode: 2,
		checkbox: true,
		selectMode: 2,
		icons: false,
		autoCollapse: true,
		source: {
			url: '/stor2rrd-cgi/genjson.sh?' + histRepQueryString('RANK')
		}
	});

	$("#voltree").fancytree({
		extensions: ["persist", "filter"],
		persist: {
			cookiePrefix: "voltree-"
		},
		filter: {
			mode: "hide",
			autoApply: true
		},
		clickFolderMode: 2,
		checkbox: true,
		selectMode: 2,
		icons: false,
		autoCollapse: true,
		source: {
			url: '/stor2rrd-cgi/genjson.sh?' + histRepQueryString('VOLUME')
		}
	});

	$("div.favs").each(function() {
		var url = $(this).parent().find('a.detail').attr('href');
		var urlObj = itemDetails(url, true);
		var hash = "";
		if (curNode.data.agg) {
			hash = urlObj.host + urlObj.type + 'SubSys_SUM';
		} else {
			hash = urlObj.host + urlObj.type + curNode.data.altname;
		}

		hash = hex_md5(hash).substring(0, 7);
		hash = hash + urlObj.itemcode + urlObj.time;
		$(this).data("gid", hash);

		if ($.inArray(hash, dbHash) >= 0) {
			$(this).removeClass("favoff"); /* Add item */
			$(this).addClass("favon");
			$(this).attr("title", "Remove this graph from Dashboard");
		} else {
			$(this).removeClass("favon");
			$(this).addClass("favoff");
			$(this).attr("title", "Add this graph to Dashboard");
		}
	});

	$("div.popdetail").each(function() {
		$(this).attr("title", "Click to show detail");
	});

	$("div.popdetail").click(function() {
		$(this).siblings("a").click();
	});

	$("div.favs").click(function() {
		var hash = $(this).data("gid");
		if ($(this).hasClass("favon")) { /* Remove item */
			$(this).removeClass("favon");
			$(this).addClass("favoff");
			$(this).attr("title", "Add this graph to Dashboard");
			var toRemove = $.inArray(hash, dbHash);
			if (toRemove >= 0) {
				dbHash.splice(toRemove, 1);
				saveCookies();
			}
		} else {
			$(this).removeClass("favoff"); /* Add item */
			$(this).addClass("favon");
			$(this).attr("title", "Remove this graph from Dashboard");
			dbHash.push(hash);
			saveCookies();
		}
	});

	function saveCookies() {
		var hashes = dbHash.join(":");
		$.cookie('dbHashes', hashes, {
			expires: 60
		});
	}


	if (!areCookiesEnabled()) {
		$("#nocookies").show();
	} else {
		$("#nocookies").hide();
		if (dbHash.length === 0) {
			$("#emptydash").show();
		} else {
			$("#emptydash").hide();
		}
	}

	if ($("#emptydash").length) {
		$( "#tabs > ul li" ).hide();
		genDashboard();
	}

	function genDashboard() {
		if ($.cookie('flatDB')) {
			$( "#tabs" ).tabs( "destroy" );
			$( "#tabs > ul" ).hide();
			$( "#tabs div" ).hide();
			$( ".dashlist p" ).show();
		}
		if (dbHash.length) {
			$.each(dbHash, function(i, val) {
				var dbItem = hashRestore(val);
				if (dbItem.lpar == 'sum') {
					dbItem.lpar = dbItem.item;
					dbItem.item = 'sum';
				}

				var complHref = urlQstring(dbItem, 1);
				var complUrl = urlQstring(dbItem, 2) + "&none=" + Math.floor(new Date().getTime() / 1000);
				var title = dbItem.host + ": ";
				if (dbItem.item == "sum") {
					if (dbItem.longname) {
						dbItem.host = dbItem.longname;
					}
					title += urlItem[dbItem.lpar] + " | ";
				} else {
					if (dbItem.longname) {
						dbItem.lpar = dbItem.longname;
					}
					var lparstr = dbItem.lpar;
					if (lparstr) {
						title += lparstr + ": " + urlItem[dbItem.item] + " | ";
					}
				}

				title += intervals[dbItem.time];

				var topTitle = dbItem.host;

				var flat = $.cookie('flatDB');

				if (dbItem.item) {
					if (dbItem.server == 'POOL') {
						$( "#tabs > ul li:eq( 0 )" ).show();
						if (flat) {
							$( "#tabs-1" ).show();
						}
						$("#dashboard-pool").append("<li><a href='" + complHref + "' class='detail'><span class='dbitemtitle'>" + topTitle + "</span></br><img class='lazy' src='css/images/sloading.gif' data-src='" + complUrl + "' title='" + title + "' alt='" + val + "'></a><div class='dash' title='Remove this item from DashBoard'></div></li>");
					} else if (dbItem.server == "RANK" || dbItem.server == "Managed disk") {
						$( "#tabs > ul li:eq( 1 )" ).show();
						if (flat) {
							$( "#tabs-2" ).show();
						}
						$("#dashboard-rank").append("<li><a href='" + complHref + "' class='detail'><span class='dbitemtitle'>" + topTitle + "</span></br><img class='lazy' src='css/images/sloading.gif' data-src='" + complUrl + "' title='" + title + "' alt='" + val + "'></a><div class='dash' title='Remove this item from DashBoard'></div></li>");
					} else if (dbItem.server == "VOLUME") {
						$( "#tabs > ul li:eq( 2 )" ).show();
						if (flat) {
							$( "#tabs-3" ).show();
						}
						$("#dashboard-volume").append("<li><a href='" + complHref + "' class='detail'><span class='dbitemtitle'>" + topTitle + "</span></br><img class='lazy' src='css/images/sloading.gif' data-src='" + complUrl + "' title='" + title + "' alt='" + val + "'></a><div class='dash' title='Remove this item from DashBoard'></div></li>");
					} else if (dbItem.server == "DRIVE") {
						$( "#tabs > ul li:eq( 3 )" ).show();
						if (flat) {
							$( "#tabs-4" ).show();
						}
						$("#dashboard-drive").append("<li><a href='" + complHref + "' class='detail'><span class='dbitemtitle'>" + topTitle + "</span></br><img class='lazy' src='css/images/sloading.gif' data-src='" + complUrl + "' title='" + title + "' alt='" + val + "'></a><div class='dash' title='Remove this item from DashBoard'></div></li>");
					} else if (dbItem.server == "PORT") {
						$( "#tabs > ul li:eq( 4 )" ).show();
						if (flat) {
							$( "#tabs-5" ).show();
						}
						$("#dashboard-port").append("<li><a href='" + complHref + "' class='detail'><span class='dbitemtitle'>" + topTitle + "</span></br><img class='lazy' src='css/images/sloading.gif' data-src='" + complUrl + "' title='" + title + "' alt='" + val + "'></a><div class='dash' title='Remove this item from DashBoard'></div></li>");
					} else if (dbItem.server == "CPU-NODE" || dbItem.server == "CPU util") {
						$( "#tabs > ul li:eq( 5 )" ).show();
						if (flat) {
							$( "#tabs-6" ).show();
						}
						$("#dashboard-cpu").append("<li><a href='" + complHref + "' class='detail'><span class='dbitemtitle'>" + topTitle + "</span></br><img class='lazy' src='css/images/sloading.gif' data-src='" + complUrl + "' title='" + title + "' alt='" + val + "'></a><div class='dash' title='Remove this item from DashBoard'></div></li>");
					} else if (dbItem.server == "HOST") {
						$( "#tabs > ul li:eq( 6 )" ).show();
						if (flat) {
							$( "#tabs-7" ).show();
						}
						$("#dashboard-host").append("<li><a href='" + complHref + "' class='detail'><span class='dbitemtitle'>" + topTitle + "</span></br><img class='lazy' src='css/images/sloading.gif' data-src='" + complUrl + "' title='" + title + "' alt='" + val + "'></a><div class='dash' title='Remove this item from DashBoard'></div></li>");
					}
				}
			});

			if ( $("#tabs > ul li:visible").length == 1) {
				$("#tabs > ul li:visible a").click();
			}

			$(".dashlist li").css({
				"width": Number(sysInfo.dashb_rrdwidth) + 75 + "px",
				"height": Number(sysInfo.dashb_rrdheight) + 60 + "px"
			//	"line-height": Number(sysInfo.dashb_rrdheight) + 60 + "px"
			});
			loadImages('#content img.lazy');
			fancyBox();

			$("div.dash").click(function() {
				var hash = $(this).parent().find('img').attr('alt');
				var toRemove = $.inArray(hash, dbHash);
				if (toRemove >= 0) {
					dbHash.splice(toRemove, 1);
					saveCookies();
					$(this).parent().hide("slow");
				}
			});
			$("ul.dashlist").sortable({
				dropOnEmpty: false
			});

			$("ul.dashlist").on("sortupdate", function(event, ui) {
				dbHash.length = 0;
				$("ul.dashlist li").find('img').each(function() {
					var hash = $(this).attr('alt');
					dbHash.push(hash);
				});
				saveCookies();
			});
		}
	}

	$("#dashfooter button").button();

	if ($.cookie('flatDB')) {
		$( "#dbstyle" ).button({ label: "Switch to Tabbed Style" });
	}

	$("#clrcookies").click(function() {
		var conf = confirm("Are you sure you want to remove all DashBoard items?");
		if (conf === true) {
			dbHash.length = 0;
			saveCookies();
			$("#side-menu").fancytree("getTree").reactivate();
		}
	});
	$("#wipecookies").button().click(function() {
		var conf = confirm("Are you sure you want to wipe all STOR2RRD cookies for this host.domain/path?");
		if (conf === true) {
			for (var it in $.cookie()) {
				$.removeCookie(it);
			}
		}
	});
	$("#envdump").button().click(function() {
		$.get("/stor2rrd-cgi/genjson.sh?jsontype=test", function(data) {
			alert(data);
		});
	});

	$("#filldash").click(function() {
		var conf = confirm("This will append predefined items: POOL IO R/W summary. Are you sure?");
		if (conf === true) {
			$.getJSON("/stor2rrd-cgi/genjson.sh?jsontype=pre", function(data) {
				$.each(data, function(key, val) {
					if ($.inArray(val, dbHash) < 0) {
						dbHash.push(val);
					}
				});
				saveCookies();
				$("#side-menu").fancytree("getTree").reactivate();
			});
		}
	});
	$("#filldashlink").click(function(event) {
		event.preventDefault();
		$("#filldash").click();
	});

	$( "#dbstyle" ).click(function() {
		if ($.cookie('flatDB')) {
			$.removeCookie('flatDB');
		} else {
			$.cookie('flatDB', true, {
				expires: 365
			});
		}
		$("#side-menu").fancytree("getTree").reactivate();
	});

	$("ul.ui-tabs-nav").hover(function() {
		if (!$("#emptydash").length) {
			$("#tabgroups").fadeIn(200);
		}
	}, function() {
		$("#tabgroups").fadeOut(100);
	});

	$('form[action="/stor2rrd-cgi/acc-wrapper.sh"]').submit(function(event) {
		event.preventDefault();
		if (timeoutHandle) {
			clearTimeout(timeoutHandle);
		}
		$('#content').empty();

		$('#content').append("<div style='width: 100%; height: 100%; text-align: center'><img src='css/images/sloading.gif' style='margin-top: 200px'></div>");
		// $('#title').text("Accounting results");
		var postData = $(this).serialize() + "&Report=Generate+Report";
		if (sysInfo.guidebug == 1) {
			copyToClipboard(postData);
		}
		$('#content').load(this.action, postData, function() {
			imgPaths();
			myreadyFunc();
		});
	});

	$( "input.allcheck" ).click(function() {
		var isChecked = this.checked;
		if ( this.name == "outdata" ) {
			$( "input:checkbox[name=output]" ).prop('checked', isChecked);
		} else {
			$( "#" + this.name + "tree").fancytree("getTree").visit(function(node) {
			if (!node.hasChildren()) {
				if (!$(node.span).hasClass("fancytree-hide")) {
					node.setSelected(isChecked);
				}
			}
			});
		}
	});
}

function itemDetails(pURL, decode) {
	var host = getUrlParameters("host", pURL, decode);
	var type = getUrlParameters("type", pURL, decode);
	var vname = getUrlParameters("name", pURL, decode);
	var item = getUrlParameters("item", pURL, false);
	var time = getUrlParameters("time", pURL, false);
	if (item == 'sum') {
		item = vname;
		vname = 'sum';
	}
	var itemcode = String.fromCharCode(97 + $.inArray(item, urlItems));
	var menutext = tabHead[item];
	return {
		"host": host,
		"type": type,
		"name": vname,
		"item": item,
		"time": time,
		"itemcode": itemcode,
		'menutext': menutext
	};
}

function hashRestore(hash) {
	var params = {};
	var i = hashTable[hash.substring(0, 7)];
	if (i) {
		var itemIndex = hash.substring(7, 8).charCodeAt(0) - 97;
		var item = urlItems[itemIndex];
		var time = hash.substring(8, 9);
		var lpar = i.lpar;
		params = {
			"host": i.hmc,
			"server": i.srv,
			"lpar": lpar,
			"item": item,
			"time": time,
			longname: i.longname
		};
	}
	return params;
}

function urlQstring(p, det) {
	var qstring = [];
	qstring.push({
		name: "host",
		value: p.host
	});
	qstring.push({
		name: "type",
		value: p.server
	});
	qstring.push({
		name: "name",
		value: p.lpar
	});
	qstring.push({
		name: "item",
		value: p.item
	});
	qstring.push({
		name: "time",
		value: p.time
	});
	qstring.push({
		name: "detail",
		value: det
	});

	return "/stor2rrd-cgi/detail-graph.sh?" + $.param(qstring);
}


function loadImages(selector) {
	$(selector).lazy({
		bind: 'event',
		/*        delay: 0, */
		effect: 'fadeIn',
		effectTime: 400,
		threshold: 100,
		appendScroll: $("div#econtent"),
		beforeLoad: function(element) {
			element.parents("td").css("vertical-align", "middle");
		},
		onLoad: function(element) {
			if ( $(element).hasClass("nolegend") ) {
				$.getJSON(element.attr("data-src"), function(data, textStatus, jqXHR) {
					var header = jqXHR.getResponseHeader('X-RRDGraph-Properties');
					if (header) {
						if (sysInfo.guidebug == 1) {
							$(element).parent().attr("title", header);
						}
						var h = header.split(":");
						var frame = $(element).siblings("div.zoom");
						$(frame).imgAreaSelect({
							remove: true
						});
						$(frame).data("graph_start", h[4]);
						$(frame).data("graph_end", h[5]);
						$(frame).css("left", h[0] + "px");
						$(frame).css("top", h[1] + "px");
						$(frame).css("width", h[2] + "px");
						$(frame).css("height", h[3] + "px");
						if (h[2] && h[3]) {
							zoomInit(frame.attr("id"), h[2], h[3]);
						}
						frame.show();
						// console.log(h);
					}
					element.attr("src", data.img);
					// loadImages(curImg);
					$(element).parents(".relpos").find("div.legend").html(Base64.decode(data.table));
					var $t = element.parents(".relpos").find('table.tablesorter');
					if ($t.length) {
						var updated = $t.find(".tdupdated");
						if (updated) {
							element.parents(".detail").siblings(".updated").text(updated.text());
							updated.parent().remove();
						}
						tableSorter($t);
						$t.find("a").click(function() {
							var url = $(this).attr('href');
							if ((url.substring(0, 7) != "http://") && (!/\.csv$/.test(url)) && (!/lpar-list-rep\.sh/.test(url)) && ($(this).text() != "CSV")) {
								backLink(url);
								return false;
							}
						});
						$t.find("td.legsq").each(function() {
							$(this).next().attr("title", $(this).next().text()); // set tooltip (to see very long names)
							var bgcolor = $(this).text();
							if (bgcolor) {
								var parLink = $(this).parents(".relpos").find("a.detail").attr("href");
								var parParams = getParams(parLink);
								// var trTime = trTime.match(/&time=([dwmy])/)[1];
								trItem = parParams.item;
								if (trItem == "sum") {
									trItem = parParams.name;
								}
								var trTime = parParams.time;
								var trLink = $(this).parent().find(".clickabletd a").last().attr("href");
								var trParams = getParams(trLink);
								if (trParams.item == "pool") {
									if (trParams.lpar == "pool") {
										trItem = "pool"
									} else {
										trItem = "shpool"
									}
								}
								trLink = "/stor2rrd-cgi/detail-graph.sh?host=" + trParams.host + "&type=" + trParams.type + "&name=" + trParams.name +
									"&item=" + trItem + "&time=" + trTime + "&detail=1&none=";
								if (trParams.name) {
									$(this).html("<a href='" + trLink + "' title='Click to get [" + decodeURIComponent(trParams.name.replace(/\+/g, " ")) + "] detail in a pop-up view' class='detail'><div class='innersq' style='background:" + bgcolor + ";'></div></a>");
									$(this).find('a.detail').fancybox({
										type: 'image',
										openEffect: 'none',
										closeEffect: 'none',
										live: false,
										openSpeed: 400,
										closeSpeed: 100,
										fitToView: false, // images won't be scaled to fit to browser's height
										maxWidth: "98%",
										overlay: {
											showEarly: false,
											css: {
												'background': 'rgba(58, 42, 45, 0.95)'
											}
										},
										closeClick: true
									});
								} else {
									$(this).html("<div class='innersq' style='background:" + bgcolor + ";'></div>");
								}
							}
						});
						if ($t.find("a.detail").length) {
							$t.find("tr").find("th").first().addClass("popup").attr("title", "Click on the color square below to get item detail in a pop-up view");
						}
						if (sysInfo.legend_height) {
								$t.parent().css("max-height", sysInfo.legend_height + "px");
						}
						$(element).parents(".relpos").find("div.legend").jScrollPane (
							{
								showArrows: false,
								horizontalGutter: 30,
								verticalGutter: 30
							}
						);
					}
					$(element).parents("td.relpos").css("vertical-align", "top");
					$(element).parents("td.relpos").css("text-align", "left");
					$(element).parents(".relpos").find("div.favs").show();
					$(element).parents(".relpos").find("div.dash").show();
					$(element).parents(".relpos").find("div.popdetail").show();
				});
			} else {
				jQuery.ajax({
					url: $(element).attr("data-src") + "&none=" + new Date().getTime(),
					//   complete: function (jqXHR, textStatus) {
					success: function(data, textStatus, jqXHR) {
						var header = jqXHR.getResponseHeader('X-RRDGraph-Properties');
						if (header) {
							if (sysInfo.guidebug == 1) {
								$(element).parent().attr("title", header);
							}
							var h = header.split(":");
							var frame = $(element).siblings("div.zoom");
							$(frame).imgAreaSelect({
								remove: true
							});
							$(frame).data("graph_start", h[4]);
							$(frame).data("graph_end", h[5]);
							$(frame).css("left", h[0] + "px");
							$(frame).css("top", h[1] + "px");
							$(frame).css("width", h[2] + "px");
							$(frame).css("height", h[3] + "px");
							if (h[2] && h[3]) {
								zoomInit(frame.attr("id"), h[2], h[3]);
							}
							frame.show();
							// console.log(h);
						}
					}
				});
			}
		},
		afterLoad: function(element) {
			$(element).removeClass('load');
			$(element).parents("td.relpos").css("vertical-align", "top");
			$(element).parents("td.relpos").css("text-align", "left");
			$(element).parents("td.relpos").find("div.favs").show();
			$(element).parents("td.relpos").find("div.dash").show();
			$(element).parents("td.relpos").find("div.popdetail").show();
		}
	});
}

function setTitle(menuitem) {
	var item = '';
	var path = '';
	var parents = menuitem.getParentList(false, true);
	var delimiter = '<span class="delimiter">&nbsp;&nbsp;|&nbsp;&nbsp;</span>';

	$.each(parents, function(key, part) {
		item = part.title;
		if (item.indexOf("STOR2RRD <span") >= 0) {
			item = "STOR2RRD";
		}
		if (item != 'Items' && item != 'Totals' && item != "STORAGE") {
			if (path === '') {
				path = item;
			} else {
				path += delimiter + item;
			}
		}
	});

	if ((curNode.key != "_1") && (curNode.title != "Historical reports") && ($('#tabs').length)) {
		var tabText = $('#tabs li.ui-tabs-active').text();
		if ( tabHead.tabText ) {
			path += delimiter + tabHead.tabText;
		} else {
			path += delimiter + tabText;
		}
	}


	$('#title').html(path);
	$('#title').show();
}

function hrefHandler() {
	$('#content a:not(.ui-tabs-anchor, .detail)').click(function() {
		var url = $(this).attr('href');
		if ((url.substring(0, 7) != "http://") && (!/\.csv$/.test(url)) && (!/lpar-list-rep\.sh/.test(url)) && ($(this).text() != "CSV")) {
			backLink(url);
			return false;
		}
	});
}

function backLink(pURL) {
	if (pURL == "#") {
		return false;
	}
	if (pURL.indexOf("?") >= 0) {
		var itemType = getUrlParameters("type", pURL, true);
		if (itemType == "POOL" || itemType == "RANK" || itemType == "PORT" || itemType == "DRIVE" || itemType == "VOLUME") {
			host = getUrlParameters("host", pURL, true);
			lpar = getUrlParameters("name", pURL, true);
			$tree = $("#side-menu").fancytree("getTree");
			$tree.visit(function(node) {
				if (node.data.altname == lpar || node.title == lpar) {
					var par1 = node.getParent(); // skip Items level
					par1 = par1.getParent();     // get class level
					if (par1.title == itemType || par1.title == (itemType=="RANK" ? "Managed disk" : "")) {
						par1 = par1.getParent();
						if (par1.title == host) {
							node.setExpanded(true);
							node.setActive();
							return false;
						}
					}
				}
			});
		}
	} else if (pURL.indexOf("gui-cpu.html") >= 0) {
		splitted = pURL.split("/");
		server = splitted[1];
		$tree = $("#side-menu").fancytree("getTree");
		$tree.visit(function(node) {
			if (node.title == "Totally for all CPU pools" || node.title == "CPU pool") {
				var par1 = node.getParent(); // skip LPARs level
				if (par1.title == server) {
					node.setExpanded(true);
					node.setActive();
					return false;
				}
			}
		});
	} else {
		var splitted = pURL.split("#");
		if (splitted[1]) {
			jumpTo = splitted[1];
		} else {
			jumpTo = "";
		}

		$('#content').load(pURL, function() {
			if (jumpTo) {
				jumpTo = decodeURI(jumpTo);
				location.hash = jumpTo;
			}
			imgPaths();
			myreadyFunc();
		});
	}
}


function getUrlParameters(parameter, url, decode) {
	var parArr = url.split("?")[1].split("&"),
		returnBool = true;

	for (var i = 0; i < parArr.length; i++) {
		parr = parArr[i].split("=");
		if (parr[0] == parameter) {
			return (decode) ? decodeURIComponent(parr[1].replace(/\+/g, " ")) : parr[1];
		} else {
			returnBool = false;
		}
	}
	if (!returnBool) {
		return false;
	}
}

function areCookiesEnabled() {
	var cookieEnabled = (navigator.cookieEnabled) ? true : false;

	if (typeof navigator.cookieEnabled == "undefined" && !cookieEnabled) {
		document.cookie = "testcookie";
		cookieEnabled = (document.cookie.indexOf("testcookie") != -1) ? true : false;
	}
	return (cookieEnabled);
}

function copyToClipboard(text) {
	window.prompt("GUI DEBUG: Please copy following content to the clipboard (Ctrl+C), then paste it to the bugreport (Ctrl-V)", text);
}

/*
function download(filename, text) {
	var pom = document.createElement('a');
	pom.setAttribute('href', 'data:text/plain;charset=utf-8,' + encodeURIComponent(text));
	pom.setAttribute('download', filename);
	pom.click();
}

function arrayBytes(arr) {
	var g = JSON.stringify(arr).replace(/[\[\]\,\"]/g, ''); //stringify and remove all "stringification" extra data
	return (g.length); //this will be your length.
}
*/

function dataSource() {
	$("#datasrc").removeClass();
	$("#datasrc").hide();
	if ($('li.tabfrontend, li.tabbackend').length > 0) {
		var activeTab = $('#tabs li.ui-tabs-active');
		var title = "Data source: ";
		var cls = "";
		if (activeTab.hasClass("tabfrontend")) {
			title += "Frontend data";
			cls = "agent";
		} else if (activeTab.hasClass("tabbackend")) {
			title += "Backend data";
			cls = "nmon";
		} else if ($('li.tabfrontend').length > 0) {
			title += "Frontend data";
			cls = "agent";
		} else {
			title += "Backend data";
			cls = "nmon";
		}
		$("#datasrc").attr("title", title);
		$("#datasrc").addClass(cls);
		$("#datasrc").show();
	} else {
		$("#datasrc").addClass("none");
	}
}

function showHideSwitch() {
	if (curNode.parent.title == "Items" && curNode.parent.parent.title == "VOLUME") {
		var dataSources = "";
		if ($("ul.ui-tabs-nav").has("li.tabfrontend").length) {
			dataSources = "frontend";
		}
		if ($("ul.ui-tabs-nav").has("li.tabbackend").length) {
			if (dataSources == "frontend") {
				dataSources = "all"; // both OS agent and NMON data present
			} else {
				dataSources = "backend"; // just NMON data present
			}
		}
		if (dataSources == "all") {
			var activeTab = $('#tabs li.ui-tabs-active.tabfrontend,#tabs li.ui-tabs-active.tabbackend').text();
			if (activeTab) {
				$("#nmonsw").show();
			} else {
				$("#nmonsw").hide();
			}
		} else {
			$("#nmonsw").hide();
		}
		agentNmonToggle(dataSources);
	} else {
		$("#nmonsw").hide();
	}
}

//*************** Toggle agent/nmon data

function agentNmonToggle(src) {
	if (src == 'all') {
		if (($("#nmr1").is(':checked')) || src == "agent") {
			$("ul.ui-tabs-nav li.tabbackend").css("display", "none");
			$("ul.ui-tabs-nav li.tabfrontend").css("display", "inline-block");
		}

		if (($("#nmr2").is(':checked')) || src == "nmon") {
			$("ul.ui-tabs-nav li.tabbackend").css("display", "inline-block");
			$("ul.ui-tabs-nav li.tabfrontend").css("display", "none");
		}
	}
}

function histRepQueryString(managedName) {
	// get HMC & server name from menu url
	// var serverPath = $("#side-menu").fancytree('getActiveNode').data.href.split('/');
	var storage = curNode.parent.title;
	var queryArr = [{
		name: 'jsontype',
		value: 'histrep'
	}, {
		name: 'hmc',
		value: storage
	}, {
		name: 'managedname',
		value: managedName
	}];
	return $.param(queryArr);
}

function sections() {
	// return;
	if (sysInfo.demo == "1") {
		var allSources = $("ul.ui-tabs-nav").has("li.tabbackend", "li.tabfrontend").length;
		if ($("li.tabhmc").length > 0) {
			$("#fsh").width(function() {
				var sectWidth = 0;
				$("li.tabhmc").each(function() {
					sectWidth += $(this).outerWidth() + 1;
				});
				return sectWidth - 1;
			});
			$("#fsh").show();
		} else {
			$("#fsh").hide();
		}

		if ($("li.tabfrontend").length > 0) {
			$("#fsa").width(function() {
				var sectWidth = 0;
				$("li.tabfrontend").each(function() {
					sectWidth += $(this).outerWidth() + 1;
				});
				return sectWidth - 1;
			});
			if (allSources === 0) {
				$("#fsa").show();
			} else if ($("#nmr1").is(':checked')) {
				$("#fsa").show();
			} else {
				$("#fsa").hide();
			}
		} else {
			$("#fsa").hide();
		}

		if ($("li.tabbackend").length > 0) {
			$("#fsn").width(function() {
				var sectWidth = 0;
				$("li.tabbackend").each(function() {
					sectWidth += $(this).outerWidth() + 1;
				});
				return sectWidth - 1;
			});
			if (allSources === 0) {
				$("#fsn").show();
			} else if ($("#nmr2").is(':checked')) {
				$("#fsn").show();
			} else {
				$("#fsn").hide();
			}
		} else {
			$("#fsn").hide();
		}
	} else {
		$("#subheader fieldset").hide();
	}
}

function tableSorter(tabletosort) {
	var sortList = {};
	$(tabletosort).find("th").each(function(i, header) {
		if (!$(header).hasClass('sortable')) {
			sortList[i] = {
				"sorter": false
			};
		}
	});
	$(tabletosort).tablesorter({
		sortInitialOrder: 'desc',
		"headers": sortList
	});
}

/*
function queryStringToHash(query) {
	var query_string = {},
		vars = query.split("&");

	for (var i = 0; i < vars.length; i++) {
		var pair = vars[i].split("=");
		pair[0] = decodeURIComponent(pair[0]);
		pair[1] = decodeURIComponent(pair[1]);
		// If first entry with this name
		if (typeof query_string[pair[0]] === "undefined") {
			query_string[pair[0]] = pair[1];
			// If second entry with this name
		} else if (typeof query_string[pair[0]] === "string") {
			var arr = [query_string[pair[0]], pair[1]];
			query_string[pair[0]] = arr;
			// If third or later entry with this name
		} else {
			query_string[pair[0]].push(pair[1]);
		}
	}
	return query_string;
}

/*
 * Returns a map of querystring parameters
 *
 * Keys of type <fieldName>[] will automatically be added to an array
 *
 * @param String url
 * @return Object parameters
 */
function getParams(url, decode) {
	var regex = /([^=&?]+)=([^&#]*)/g,
		params = {},
		parts, key, value;

	while ((parts = regex.exec(url)) != null) {

		key = parts[1];
		value = parts[2];
		if (decode) {
			value = decodeURIComponent(value);
		}
		var isArray = /\[\]$/.test(key);

		if (isArray) {
			params[key] = params[key] || [];
			params[key].push(value);
		} else {
			params[key] = value;
		}
	}

	return params;
}

/*
function ShowDate(ts) {
	var then = ts.getFullYear() + '-' + (ts.getMonth() + 1) + '-' + ts.getDay();
	then += ' ' + ts.getHours() + ':' + ts.getMinutes();
	return (then);
}
*/

function zoomInit(zoomID, width, height) {
	$("#" + zoomID).imgAreaSelect({
		handles: false,
		maxHeight: height,
		minHeight: height,
		maxWidth: width,
		parent: "#content",
		fadeSpeed: 500,
		autoHide: true,
		onSelectEnd: function(img, selection) {
			if (selection.width) {
				var from = new Date($(img).data().graph_start * 1000);
				var to = new Date($(img).data().graph_end * 1000);
				var timePerPixel = (to - from) / $(img).width();
				var selFrom = new Date(+from + selection.x1 * timePerPixel);
				var selTo = new Date(+selFrom + selection.width * timePerPixel);
				storedObj = $(img).parents("a.detail");
				storedUrl = $(storedObj).attr("href");
				var nonePos = storedUrl.indexOf('&none');
				zoomedUrl = storedUrl.slice(0, nonePos);
				zoomedUrl += "&sunix=" + selFrom.getTime() / 1000;
				zoomedUrl += "&eunix=" + selTo.getTime() / 1000;
				$(storedObj).attr("href", zoomedUrl);
				$(storedObj).click();
			}
		}
	});
}

/* placeholder for input fields */
function placeholder() {
	$("input[type=text]").each(function() {
		var phvalue = $(this).attr("placeholder");
		$(this).val(phvalue);
	});
}

function CheckExtension(file) {
	/*global document: false */
	var validFilesTypes = ["nmon", "csv"];
	var filePath = file.value;
	var ext = filePath.substring(filePath.lastIndexOf('.') + 1).toLowerCase();
	var isValidFile = false;

	for (var i = 0; i < validFilesTypes.length; i++) {
		if (ext == validFilesTypes[i]) {
			isValidFile = true;
			break;
		}
	}

	if (!isValidFile) {
		file.value = null;
		alert("Invalid File. Valid extensions are:\n\n" + validFilesTypes.join(", "));
	}

	return isValidFile;
}

function getUrlParameter(sParam)
{
	var sPageURL = window.location.search.substring(1);
	var sURLVariables = sPageURL.split('&');
	for (var i = 0; i < sURLVariables.length; i++)
	{
		var sParameterName = sURLVariables[i].split('=');
		if (sParameterName[0] == sParam)
		{
			return sParameterName[1];
		}
	}
}

function saveData (id) {
	if (!sessionStorage) {
		return;
	}
	var data = {
		id: id,
		scroll: $("#content").scrollTop(),
		title: $("#title").html(),
		html: $("#content").html()
	};
	sessionStorage.setItem(id,JSON.stringify(data));
}
function restoreData (id) {
    if (!sessionStorage) {
        return;
	}
    var data = sessionStorage.getItem(id);
    if (!data) {
        return null;
	}
    return JSON.parse(data);
}

function detectIE() {
    var ua = window.navigator.userAgent;
    var msie = ua.indexOf('MSIE ');
    var trident = ua.indexOf('Trident/');

    if (msie > 0) {
        // IE 10 or older => return version number
        return parseInt(ua.substring(msie + 5, ua.indexOf('.', msie)), 10);
    }

    if (trident > 0) {
        // IE 11 (or newer) => return version number
        var rv = ua.indexOf('rv:');
        return parseInt(ua.substring(rv + 3, ua.indexOf('.', rv)), 10);
    }

    // other browser
    return false;
}

// Create Base64 Object
var Base64={_keyStr:"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/=",encode:function(e){var t="";var n,r,i,s,o,u,a;var f=0;e=Base64._utf8_encode(e);while(f<e.length){n=e.charCodeAt(f++);r=e.charCodeAt(f++);i=e.charCodeAt(f++);s=n>>2;o=(n&3)<<4|r>>4;u=(r&15)<<2|i>>6;a=i&63;if(isNaN(r)){u=a=64}else if(isNaN(i)){a=64}t=t+this._keyStr.charAt(s)+this._keyStr.charAt(o)+this._keyStr.charAt(u)+this._keyStr.charAt(a)}return t},decode:function(e){var t="";var n,r,i;var s,o,u,a;var f=0;e=e.replace(/[^A-Za-z0-9\+\/\=]/g,"");while(f<e.length){s=this._keyStr.indexOf(e.charAt(f++));o=this._keyStr.indexOf(e.charAt(f++));u=this._keyStr.indexOf(e.charAt(f++));a=this._keyStr.indexOf(e.charAt(f++));n=s<<2|o>>4;r=(o&15)<<4|u>>2;i=(u&3)<<6|a;t=t+String.fromCharCode(n);if(u!=64){t=t+String.fromCharCode(r)}if(a!=64){t=t+String.fromCharCode(i)}}t=Base64._utf8_decode(t);return t},_utf8_encode:function(e){e=e.replace(/\r\n/g,"\n");var t="";for(var n=0;n<e.length;n++){var r=e.charCodeAt(n);if(r<128){t+=String.fromCharCode(r)}else if(r>127&&r<2048){t+=String.fromCharCode(r>>6|192);t+=String.fromCharCode(r&63|128)}else{t+=String.fromCharCode(r>>12|224);t+=String.fromCharCode(r>>6&63|128);t+=String.fromCharCode(r&63|128)}}return t},_utf8_decode:function(e){var t="";var n=0;var r=c1=c2=0;while(n<e.length){r=e.charCodeAt(n);if(r<128){t+=String.fromCharCode(r);n++}else if(r>191&&r<224){c2=e.charCodeAt(n+1);t+=String.fromCharCode((r&31)<<6|c2&63);n+=2}else{c2=e.charCodeAt(n+1);c3=e.charCodeAt(n+2);t+=String.fromCharCode((r&15)<<12|(c2&63)<<6|c3&63);n+=3}}return t}}

function groupTable($rows, startIndex, total) {
	if (total === 0) {
		return;
	}
	var i , currentIndex = startIndex, count=1, lst=[];
	var tds = $rows.find('td:eq('+ currentIndex +')');
	var ctrl = $(tds[0]);
	lst.push($rows[0]);
	for (i=1;i<=tds.length;i++) {
		if (ctrl.text() ==  $(tds[i]).text()) {
			count++;
			$(tds[i]).addClass('deleted');
			lst.push($rows[i]);
		} else {
			if (count>1) {
				ctrl.attr('rowspan',count);
				groupTable($(lst),startIndex+1,total-1)
			}
			count=1;
			lst = [];
			ctrl=$(tds[i]);
			lst.push($rows[i]);
		}
	}
}
